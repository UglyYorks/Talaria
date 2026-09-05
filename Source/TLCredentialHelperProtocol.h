#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <xpc/xpc.h>

#define TL_CREDENTIAL_HELPER_SERVICE "com.talaria.chat.credentials-helper"
#define TL_CREDENTIAL_HELPER_IDENTIFIER @"com.talaria.chat.credentials-helper"

// Pin the peer to our own leaf certificate, not merely a bundle identifier or
// a caller-supplied path. XPC checks every message against this requirement.
static inline NSString *TLCredentialPeerRequirement(NSString *identifier) {
  SecCodeRef code = NULL;
  CFDictionaryRef information = NULL;
  if (SecCodeCopySelf(kSecCSDefaultFlags, &code) != errSecSuccess) return nil;
  OSStatus status = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &information);
  CFRelease(code);
  if (status != errSecSuccess) return nil;
  NSDictionary *info = CFBridgingRelease(information);
  NSArray *certificates = info[(__bridge id)kSecCodeInfoCertificates];
  if (!certificates.count) return nil;
  NSData *certificate = CFBridgingRelease(SecCertificateCopyData((__bridge SecCertificateRef)certificates[0]));
  unsigned char digest[CC_SHA1_DIGEST_LENGTH];
  CC_SHA1(certificate.bytes, (CC_LONG)certificate.length, digest);
  NSMutableString *hash = [NSMutableString string];
  for (NSUInteger i = 0; i < sizeof(digest); i++) [hash appendFormat:@"%02x", digest[i]];
  return [NSString stringWithFormat:@"identifier \"%@\" and certificate leaf = H\"%@\"", identifier, hash];
}
