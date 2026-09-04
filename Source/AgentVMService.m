#import "AgentVMService.h"
#import <Virtualization/Virtualization.h>

static NSString * const TLAgentVMErrorDomain = @"Talaria.AgentVM";
static NSString * const TLAgentRuntimeDirectoryName = @"AgentRuntime/linux-arm64";
static NSString * const TLAgentRuntimeKernelName = @"Image";
static NSString * const TLAgentRuntimeInitialRamdiskName = @"initrd";
static NSString * const TLAgentRuntimeRootDiskName = @"root.img";
static NSString * const TLAgentRuntimeMachineIdentifierName = @"machine.identifier";
static NSString * const TLAgentConsoleLogName = @"console.log";
static NSString * const TLAgentSharedDirectoryName = @"workspace";
static NSTimeInterval const TLAgentVMConnectionRetryDelay = 0.25;

static NSError *TLAgentVMError(NSString *message) {
  return [NSError errorWithDomain:TLAgentVMErrorDomain
                             code:1
                         userInfo:@{NSLocalizedDescriptionKey: message ?: @""}];
}

static NSString *TLAgentTrim(NSString *value) {
  return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@interface TLAgentVMService ()

@property (nonatomic, strong) NSURL *agentsDirectoryURL;
@property (nonatomic, strong) NSURL *runtimeBundleURL;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, VZVirtualMachine *> *runningVMs;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray *> *pendingStartCompletions;

@end

@implementation TLAgentVMService

+ (NSURL *)defaultAgentsDirectoryURL {
  NSURL *supportURL = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
  return [[supportURL URLByAppendingPathComponent:@"com.talaria.chat" isDirectory:YES]
    URLByAppendingPathComponent:@"Agents" isDirectory:YES];
}

+ (NSURL *)defaultRuntimeBundleURL {
  NSURL *bundledRuntimeURL = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:TLAgentRuntimeDirectoryName isDirectory:YES];
  BOOL isBundledRuntimeDirectory = NO;
  if ([NSFileManager.defaultManager fileExistsAtPath:bundledRuntimeURL.path isDirectory:&isBundledRuntimeDirectory] && isBundledRuntimeDirectory) {
    return bundledRuntimeURL;
  }

  NSURL *supportURL = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
  return [[supportURL URLByAppendingPathComponent:@"com.talaria.chat" isDirectory:YES]
    URLByAppendingPathComponent:TLAgentRuntimeDirectoryName isDirectory:YES];
}

- (instancetype)init {
  return [self initWithAgentsDirectoryURL:self.class.defaultAgentsDirectoryURL
                         runtimeBundleURL:self.class.defaultRuntimeBundleURL];
}

- (instancetype)initWithAgentsDirectoryURL:(NSURL *)agentsDirectoryURL
                          runtimeBundleURL:(NSURL *)runtimeBundleURL {
  self = [super init];
  if (self) {
    _agentsDirectoryURL = agentsDirectoryURL;
    _runtimeBundleURL = runtimeBundleURL;
    _runningVMs = [NSMutableDictionary dictionary];
    _pendingStartCompletions = [NSMutableDictionary dictionary];
  }
  return self;
}

- (BOOL)isVirtualizationSupported {
  return VZVirtualMachine.supported;
}

- (NSString *)newVMDirectoryPathForAgentName:(NSString *)name {
  NSString *identifier = [NSString stringWithFormat:@"%@-%@", [self sanitizedName:name], NSUUID.UUID.UUIDString];
  return [self.agentsDirectoryURL URLByAppendingPathComponent:identifier isDirectory:YES].path;
}

- (BOOL)prepareStorageForAgent:(TLAgentRecord *)agent error:(NSError **)error {
  if (agent.vmDirectory.length == 0) {
    if (error) {
      *error = TLAgentVMError(@"Agent VM directory is missing.");
    }
    return NO;
  }

  NSURL *vmDirectoryURL = [NSURL fileURLWithPath:agent.vmDirectory isDirectory:YES];
  NSURL *sharedDirectoryURL = [vmDirectoryURL URLByAppendingPathComponent:TLAgentSharedDirectoryName isDirectory:YES];
  NSFileManager *fileManager = NSFileManager.defaultManager;
  return [fileManager createDirectoryAtURL:sharedDirectoryURL
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:error];
}

- (void)startAgent:(TLAgentRecord *)agent completion:(TLAgentVMCompletionHandler)completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSNumber *key = @(agent.agentID);
    VZVirtualMachine *existingVirtualMachine = self.runningVMs[key];
    if (existingVirtualMachine.state == VZVirtualMachineStateRunning) {
      if (completion) {
        completion(nil);
      }
      return;
    }
    if (existingVirtualMachine.state == VZVirtualMachineStateStarting) {
      [self enqueueStartCompletion:completion key:key];
      return;
    }
    if (existingVirtualMachine && !existingVirtualMachine.canStart) {
      if (completion) {
        completion(TLAgentVMError(@"Agent VM cannot be started from its current state."));
      }
      return;
    }

    NSError *error = nil;
    VZVirtualMachine *virtualMachine = [self virtualMachineForAgent:agent error:&error];
    if (!virtualMachine) {
      if (completion) {
        completion(error);
      }
      return;
    }

    self.runningVMs[key] = virtualMachine;
    [self enqueueStartCompletion:completion key:key];
    [virtualMachine startWithCompletionHandler:^(NSError *startError) {
      if (startError) {
        [self.runningVMs removeObjectForKey:key];
      }
      [self drainStartCompletionsForKey:key error:startError];
    }];
  });
}

- (void)stopAgent:(TLAgentRecord *)agent completion:(TLAgentVMCompletionHandler)completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSNumber *key = @(agent.agentID);
    VZVirtualMachine *virtualMachine = self.runningVMs[key];
    if (!virtualMachine) {
      if (completion) {
        completion(nil);
      }
      return;
    }

    if (!virtualMachine.canStop) {
      if (completion) {
        completion(TLAgentVMError(@"Agent VM cannot be stopped from its current state."));
      }
      return;
    }

    [virtualMachine stopWithCompletionHandler:^(NSError *stopError) {
      if (!stopError) {
        [self.runningVMs removeObjectForKey:key];
      }
      if (completion) {
        completion(stopError);
      }
    }];
  });
}

- (void)connectToAgent:(TLAgentRecord *)agent
                  port:(uint32_t)port
               timeout:(NSTimeInterval)timeout
            completion:(TLAgentVMConnectionCompletionHandler)completion {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSNumber *key = @(agent.agentID);
    VZVirtualMachine *virtualMachine = self.runningVMs[key];
    if (!virtualMachine || virtualMachine.state != VZVirtualMachineStateRunning) {
      if (completion) {
        completion(nil, TLAgentVMError(@"Agent VM is not running."));
      }
      return;
    }

    VZVirtioSocketDevice *socketDevice = [self socketDeviceForVirtualMachine:virtualMachine];
    if (!socketDevice) {
      if (completion) {
        completion(nil, TLAgentVMError(@"Agent VM has no virtio socket device."));
      }
      return;
    }

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:MAX(timeout, TLAgentVMConnectionRetryDelay)];
    [self connectToSocketDevice:socketDevice port:port deadline:deadline completion:completion];
  });
}

- (BOOL)deleteVMForAgent:(TLAgentRecord *)agent error:(NSError **)error {
  if (self.runningVMs[@(agent.agentID)] != nil) {
    if (error) {
      *error = TLAgentVMError(@"Stop the agent before deleting it.");
    }
    return NO;
  }

  if (agent.vmDirectory.length == 0) {
    return YES;
  }

  NSURL *vmDirectoryURL = [NSURL fileURLWithPath:agent.vmDirectory isDirectory:YES];
  if (![NSFileManager.defaultManager fileExistsAtPath:vmDirectoryURL.path]) {
    return YES;
  }

  return [NSFileManager.defaultManager removeItemAtURL:vmDirectoryURL error:error];
}

- (BOOL)isAgentRunning:(TLAgentRecord *)agent {
  VZVirtualMachine *virtualMachine = self.runningVMs[@(agent.agentID)];
  return virtualMachine.state == VZVirtualMachineStateRunning;
}

- (VZVirtualMachine *)virtualMachineForAgent:(TLAgentRecord *)agent error:(NSError **)error {
  if (!self.virtualizationSupported) {
    if (error) {
      *error = TLAgentVMError(@"Virtualization.framework is not available on this Mac.");
    }
    return nil;
  }

  if (![self prepareStorageForAgent:agent error:error]) {
    return nil;
  }

  NSURL *kernelURL = [self.runtimeBundleURL URLByAppendingPathComponent:TLAgentRuntimeKernelName];
  NSURL *initialRamdiskURL = [self.runtimeBundleURL URLByAppendingPathComponent:TLAgentRuntimeInitialRamdiskName];
  NSURL *rootDiskURL = [self.runtimeBundleURL URLByAppendingPathComponent:TLAgentRuntimeRootDiskName];
  if (![self fileExistsAtURL:kernelURL] || ![self fileExistsAtURL:initialRamdiskURL]) {
    if (error) {
      *error = TLAgentVMError([NSString stringWithFormat:@"Linux runtime bundle is missing %@ or %@ at %@.",
                                                        TLAgentRuntimeKernelName,
                                                        TLAgentRuntimeInitialRamdiskName,
                                                        self.runtimeBundleURL.path]);
    }
    return nil;
  }

  VZLinuxBootLoader *bootLoader = [[VZLinuxBootLoader alloc] initWithKernelURL:kernelURL];
  bootLoader.initialRamdiskURL = initialRamdiskURL;
  bootLoader.commandLine = @"quiet console=hvc0 rdinit=/talaria-init ip=dhcp panic=1";

  VZGenericPlatformConfiguration *platform = [[VZGenericPlatformConfiguration alloc] init];
  platform.machineIdentifier = [self machineIdentifierForAgent:agent error:error];
  if (!platform.machineIdentifier) {
    return nil;
  }

  VZVirtualMachineConfiguration *configuration = [[VZVirtualMachineConfiguration alloc] init];
  configuration.platform = platform;
  configuration.CPUCount = [self clampedCPUCount:2];
  configuration.memorySize = [self clampedMemorySize:2ULL * 1024ULL * 1024ULL * 1024ULL];
  configuration.bootLoader = bootLoader;
  configuration.entropyDevices = @[[[VZVirtioEntropyDeviceConfiguration alloc] init]];
  configuration.networkDevices = @[[self NATNetworkDevice]];
  configuration.serialPorts = [self serialPortsForAgent:agent error:error];
  if (!configuration.serialPorts) {
    return nil;
  }
  configuration.socketDevices = @[[[VZVirtioSocketDeviceConfiguration alloc] init]];
  configuration.storageDevices = [self storageDevicesForRootDiskURL:rootDiskURL error:error];
  if (!configuration.storageDevices) {
    return nil;
  }
  configuration.directorySharingDevices = @[[self directorySharingDeviceForAgent:agent]];

  NSError *validationError = nil;
  if (![configuration validateWithError:&validationError]) {
    if (error) {
      *error = validationError;
    }
    return nil;
  }

  return [[VZVirtualMachine alloc] initWithConfiguration:configuration];
}

- (NSArray<VZSerialPortConfiguration *> *)serialPortsForAgent:(TLAgentRecord *)agent error:(NSError **)error {
  NSURL *consoleLogURL = [[NSURL fileURLWithPath:agent.vmDirectory isDirectory:YES]
    URLByAppendingPathComponent:TLAgentConsoleLogName];
  VZFileSerialPortAttachment *attachment = [[VZFileSerialPortAttachment alloc] initWithURL:consoleLogURL
                                                                                   append:NO
                                                                                    error:error];
  if (!attachment) {
    return nil;
  }

  VZVirtioConsoleDeviceSerialPortConfiguration *serialPort = [[VZVirtioConsoleDeviceSerialPortConfiguration alloc] init];
  serialPort.attachment = attachment;
  return @[serialPort];
}

- (VZGenericMachineIdentifier *)machineIdentifierForAgent:(TLAgentRecord *)agent error:(NSError **)error {
  NSURL *identifierURL = [[NSURL fileURLWithPath:agent.vmDirectory isDirectory:YES]
    URLByAppendingPathComponent:TLAgentRuntimeMachineIdentifierName];
  NSData *storedIdentifierData = [NSData dataWithContentsOfURL:identifierURL options:0 error:nil];
  if (storedIdentifierData.length > 0) {
    VZGenericMachineIdentifier *storedIdentifier = [[VZGenericMachineIdentifier alloc] initWithDataRepresentation:storedIdentifierData];
    if (storedIdentifier) {
      return storedIdentifier;
    }

    if (error) {
      *error = TLAgentVMError(@"Agent VM machine identifier is invalid.");
    }
    return nil;
  }

  VZGenericMachineIdentifier *machineIdentifier = [[VZGenericMachineIdentifier alloc] init];
  if (![machineIdentifier.dataRepresentation writeToURL:identifierURL options:NSDataWritingAtomic error:error]) {
    return nil;
  }
  return machineIdentifier;
}

- (void)enqueueStartCompletion:(TLAgentVMCompletionHandler)completion key:(NSNumber *)key {
  if (!completion) {
    return;
  }

  NSMutableArray *completions = self.pendingStartCompletions[key];
  if (!completions) {
    completions = [NSMutableArray array];
    self.pendingStartCompletions[key] = completions;
  }
  [completions addObject:[completion copy]];
}

- (void)drainStartCompletionsForKey:(NSNumber *)key error:(NSError *)error {
  NSArray *completions = [self.pendingStartCompletions[key] copy];
  [self.pendingStartCompletions removeObjectForKey:key];
  for (TLAgentVMCompletionHandler completion in completions) {
    completion(error);
  }
}

- (VZVirtioSocketDevice *)socketDeviceForVirtualMachine:(VZVirtualMachine *)virtualMachine {
  for (VZSocketDevice *socketDevice in virtualMachine.socketDevices) {
    if ([socketDevice isKindOfClass:VZVirtioSocketDevice.class]) {
      return (VZVirtioSocketDevice *)socketDevice;
    }
  }

  return nil;
}

- (void)connectToSocketDevice:(VZVirtioSocketDevice *)socketDevice
                         port:(uint32_t)port
                     deadline:(NSDate *)deadline
                   completion:(TLAgentVMConnectionCompletionHandler)completion {
  [socketDevice connectToPort:port completionHandler:^(VZVirtioSocketConnection *connection, NSError *error) {
    if (connection) {
      if (completion) {
        completion(connection, nil);
      }
      return;
    }

    if ([deadline timeIntervalSinceNow] <= 0.0) {
      if (completion) {
        completion(nil, error ?: TLAgentVMError(@"Timed out waiting for the agent service in the VM."));
      }
      return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(TLAgentVMConnectionRetryDelay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
      [self connectToSocketDevice:socketDevice port:port deadline:deadline completion:completion];
    });
  }];
}

- (NSArray<VZStorageDeviceConfiguration *> *)storageDevicesForRootDiskURL:(NSURL *)rootDiskURL error:(NSError **)error {
  if (![self fileExistsAtURL:rootDiskURL]) {
    return @[];
  }

  VZDiskImageStorageDeviceAttachment *attachment = [[VZDiskImageStorageDeviceAttachment alloc] initWithURL:rootDiskURL
                                                                                                 readOnly:NO
                                                                                                    error:error];
  if (!attachment) {
    return nil;
  }

  return @[[[VZVirtioBlockDeviceConfiguration alloc] initWithAttachment:attachment]];
}

- (VZVirtioNetworkDeviceConfiguration *)NATNetworkDevice {
  VZVirtioNetworkDeviceConfiguration *networkDevice = [[VZVirtioNetworkDeviceConfiguration alloc] init];
  networkDevice.attachment = [[VZNATNetworkDeviceAttachment alloc] init];
  return networkDevice;
}

- (VZVirtioFileSystemDeviceConfiguration *)directorySharingDeviceForAgent:(TLAgentRecord *)agent {
  NSURL *sharedDirectoryURL = [[NSURL fileURLWithPath:agent.vmDirectory isDirectory:YES]
    URLByAppendingPathComponent:TLAgentSharedDirectoryName isDirectory:YES];
  VZSharedDirectory *sharedDirectory = [[VZSharedDirectory alloc] initWithURL:sharedDirectoryURL readOnly:NO];
  VZVirtioFileSystemDeviceConfiguration *fileSystem = [[VZVirtioFileSystemDeviceConfiguration alloc] initWithTag:@"talaria"];
  fileSystem.share = [[VZSingleDirectoryShare alloc] initWithDirectory:sharedDirectory];
  return fileSystem;
}

- (NSUInteger)clampedCPUCount:(NSUInteger)requestedCPUCount {
  NSUInteger minimumCPUCount = VZVirtualMachineConfiguration.minimumAllowedCPUCount;
  NSUInteger maximumCPUCount = VZVirtualMachineConfiguration.maximumAllowedCPUCount;
  return MIN(maximumCPUCount, MAX(minimumCPUCount, requestedCPUCount));
}

- (uint64_t)clampedMemorySize:(uint64_t)requestedMemorySize {
  uint64_t minimumMemorySize = VZVirtualMachineConfiguration.minimumAllowedMemorySize;
  uint64_t maximumMemorySize = VZVirtualMachineConfiguration.maximumAllowedMemorySize;
  uint64_t oneMegabyte = 1024ULL * 1024ULL;
  uint64_t roundedMemorySize = (requestedMemorySize / oneMegabyte) * oneMegabyte;
  return MIN(maximumMemorySize, MAX(minimumMemorySize, roundedMemorySize));
}

- (BOOL)fileExistsAtURL:(NSURL *)URL {
  BOOL isDirectory = NO;
  return [NSFileManager.defaultManager fileExistsAtPath:URL.path isDirectory:&isDirectory] && !isDirectory;
}

- (NSString *)sanitizedName:(NSString *)name {
  NSString *trimmedName = TLAgentTrim(name ?: @"");
  if (trimmedName.length == 0) {
    trimmedName = @"agent";
  }

  NSMutableCharacterSet *allowedCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
  [allowedCharacters addCharactersInString:@"-_"];
  NSMutableString *sanitized = [NSMutableString string];
  for (NSUInteger index = 0; index < trimmedName.length; index += 1) {
    unichar character = [trimmedName characterAtIndex:index];
    [sanitized appendString:[allowedCharacters characterIsMember:character]
      ? [NSString stringWithCharacters:&character length:1]
      : @"-"];
  }

  return sanitized.length > 0 ? sanitized : @"agent";
}

@end
