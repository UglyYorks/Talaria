(() => {
  'use strict';
  const {Editor, StarterKit, Markdown, TableKit, TaskList, TaskItem, Image, marked} = TalariaEditorDependencies;
  let editor, epoch = 0, sequence = 0, original = '', initialDoc, editable = false;
  const post = payload => window.webkit?.messageHandlers.notesEditor.postMessage(payload);
  const markdown = () => editor.state.doc.eq(initialDoc) ? original : editor.getMarkdown();
  const state = () => ({bold:editor.isActive('bold'), italic:editor.isActive('italic'),
    title:editor.isActive('heading',{level:1}), heading:editor.isActive('heading',{level:2}), bullet:editor.isActive('bulletList'), ordered:editor.isActive('orderedList'),
    task:editor.isActive('taskList'), quote:editor.isActive('blockquote'), code:editor.isActive('codeBlock'),
    link:editor.isActive('link'), table:editor.isActive('table')});
  function snapshot() {
    return {epoch, sequence:++sequence, markdown:markdown(), composing:editor.view.composing,
      state:state(), href:editor.getAttributes('link').href || ''};
  }
  function emit() {
    if (!editor || editor.view.composing) return;
    post({type:'change', ...snapshot()});
  }
  function needsSource(text) {
    // Embedded HTML (including comments) and metadata must never be silently
    // stripped by the rich-text schema. Keep these documents in Markdown view.
    let html = false;
    marked.walkTokens(marked.lexer(text), token => { if (token.type === 'html' || token.type === 'def') html = true; });
    return html || /^---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)\s*(?:\r?\n|$)/.test(text);
  }
  window.TalariaNotes = {
    load(text, identity, canEdit) {
      if (editor) editor.destroy();
      epoch = identity; sequence = 0; original = text; editable = canEdit;
      const sourceRequired = needsSource(text);
      editor = new Editor({element:document.getElementById('editor'),
        extensions:[StarterKit.configure({underline:false, link:{openOnClick:false, autolink:false},
          dropcursor:false, trailingNode:false}), Markdown, TableKit.configure({table:{resizable:false}}),
          TaskList, TaskItem.configure({nested:true}), Image.configure({inline:true,allowBase64:true})],
        content:text, contentType:'markdown', editable:canEdit && !sourceRequired,
        editorProps:{attributes:{role:'textbox','aria-label':'Formatted note', 'aria-multiline':'true',spellcheck:'true'},
          handleDOMEvents:{compositionend:() => {setTimeout(emit,0); return false;}}},
        onUpdate:emit,
        onSelectionUpdate:() => post({type:'selection',epoch,state:state()})});
      initialDoc = editor.state.doc;
      return {sourceRequired, ...snapshot()};
    },
    snapshot,
    focus() { editor?.commands.focus(); },
    setEditable(value) { editable = value; editor?.setEditable(value, false); },
    command(name, value) {
      if (!editable || !editor) return;
      const chain = editor.chain().focus();
      const commands = {bold:() => chain.toggleBold(), italic:() => chain.toggleItalic(),
        heading:() => chain.toggleHeading({level:2}), title:() => chain.toggleHeading({level:1}),
        paragraph:() => chain.setParagraph(), bullet:() => chain.toggleBulletList(),
        ordered:() => chain.toggleOrderedList(), task:() => chain.toggleTaskList(),
        quote:() => chain.toggleBlockquote(), code:() => chain.toggleCodeBlock(),
        undo:() => chain.undo(), redo:() => chain.redo(),
        table:() => editor.isActive('table') ? chain.addRowAfter() : chain.insertTable({rows:3,cols:2,withHeaderRow:true}),
        link:() => value ? chain.extendMarkRange('link').setLink({href:value}) : chain.extendMarkRange('link').unsetLink()};
      commands[name]?.().run();
    },
    theme(tokens) {
      for (const [key,value] of Object.entries(tokens)) document.documentElement.style.setProperty('--'+key,value);
    }
  };
  document.addEventListener('click', event => { if (event.target.closest('a')) event.preventDefault(); });
  post({type:'ready'});
})();
