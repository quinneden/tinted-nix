/*
  This was not written by me!
  Original can be found at https://github.com/SenchoPens/fromYaml/blob/main/fromYaml.nix,
  I just copied it here for convenience and to avoid adding another flake input.

  This is a yaml parser.
  This is the result of a lot of trial and error and does not implement the full
  yaml spec, but it seems to be relatively efficient.
  It can parse larger yaml files with 1MB+ without a problem (if those do not
  make use of unsupported yaml features).
  EDIT: It seems to do weird things with some documents. This is definitely not reliable!
  TODO: add support for multi line strings
*/
{
  lib ? (import <nixpkgs> { }).lib,
  ...
}:
let
  l =
    lib
    // builtins
    // {
      # I'm going to cry on Nix's naming convention
      foldl = lib.foldl or lib.foldl' or builtins.foldl or builtins.foldl';
    };

  parseValue =
    value':
    let
      value = builtins.elemAt (builtins.match ''(^[^"'#]*["'][^"']*["'][^#]*|^[^#]*)($|#.*$)'' value') 0; # from Misterio77/nix-colors
      is = re: l.match re value != null;
      contentOf = re: l.elemAt (l.match re value) 0;
      singleQuotedString = "[[:space:]]*'([^']*)'[[:space:]]*";
      doubleQuotedString = ''[[:space:]]*"([^"]*)"[[:space:]]*'';
      abbreviatedList = ''[[:space:]]*\[(.*)][[:space:]]*'';
      parseAbbreviatedListContent = c: map parseValue (l.splitString "," c);
    in
    if is singleQuotedString then
      contentOf singleQuotedString
    else if is doubleQuotedString then
      contentOf doubleQuotedString
    else if is abbreviatedList then
      parseAbbreviatedListContent (contentOf abbreviatedList)
    else
      value;

  parse =
    text:
    let
      lines = l.splitString "\n" text;

      # filter out comments and empty lines
      # TODO: filter out comments where there are spaces in front of th `#`
      # TODO: filter out comments at the end of a line
      filtered = l.filter (
        line: (l.match ''[[:space:]]*'' line == null) && (!l.hasPrefix "#" line)
      ) lines;

      # extract indent, key, value, isListEntry for each line
      matched = l.map (line: matchLine line) filtered;

      # Match each line to get: indent, key, value, isListEntry
      # If a key value expression spans multiple lines,
      # the value of the current line will be defined null
      matchLine =
        line:
        let
          # single line key value statement
          m1 = l.match ''([ -]*)(.*):[[:space:]]+(.+)'' line;
          # multi line key value (line contains only key)
          m2 = l.match ''([ -]*)(.*):[[:space:]]*'' line;
          # is the line starting a new list element?
          m3 = l.match ''([[:space:]]*-[[:space:]]+)(.*)'' line;
        in
        # handle list elements (lines starting with ' -')
        if m3 != null then
          {
            isListEntry = true;
            indent = l.stringLength (l.elemAt m3 0);
            key = if m1 != null then l.elemAt m1 1 else null;
            value = parseValue (if m1 != null then l.elemAt m1 2 else l.elemAt m3 1);
          }
        # handle single line key -> val assignments
        else if m1 != null then
          {
            isListEntry = false;
            indent = l.stringLength (l.elemAt m1 0);
            key = l.elemAt m1 1;
            value = parseValue (l.elemAt m1 2);
          }
        # handle multi-line key -> object assignment
        else if m2 != null then
          {
            isListEntry = false;
            indent = l.stringLength (l.elemAt m2 0);
            key = l.elemAt m2 1;
            value = null;
          }
        else
          null;

      # store total number of lines
      numLines = l.length filtered;

      /*
        Process line by line via a deep recursion, so that this function is
        executed once on each line.
        It is each iterations `responsibility` to traverse through it's children
        (for example list elements under a key), and merge/update these correctly
        with itself.
        By looking at the regex result of the current line and the next line,
        we know what type of structure the current line creates, if it has any
        children, and what is the type of the children's structure.
      */
      make =
        lines: i:
        let
          mNext = l.elemAt matched (i + 1);
          m = l.elemAt matched i;
          currIndent = if i == -1 then -1 else m.indent;
          next = make lines (i + 1);
          childrenMustBeList = mNext.indent > currIndent && mNext.isListEntry;

          findChildIdxs =
            searchIdx:
            let
              mSearch = l.elemAt matched searchIdx;
            in
            if searchIdx >= numLines then
              [ ]
            else if mSearch.indent > childIndent then
              findChildIdxs (searchIdx + 1)
            else if mSearch.indent == childIndent then
              if mSearch.isListEntry == childrenMustBeList then
                [ searchIdx ] ++ findChildIdxs (searchIdx + 1)
              else
                findChildIdxs (searchIdx + 1)
            else
              [ ];

          childIndent = if mNext.indent > currIndent then mNext.indent else null;

          childIdxs = if childIndent == null then [ ] else findChildIdxs (i + 1);

          childObjects = l.map (sIdx: make lines sIdx) childIdxs;

          childrenMerged = l.foldl (
            all: cObj:
            (
              if l.isAttrs cObj then
                (if all == null then { } else all) // cObj
              else
                (if all == null then [ ] else all) ++ cObj
            )
          ) null childObjects;

          result =
            if i == (-1) then
              childrenMerged
            else if m.isListEntry then
              # has key and value -> check if attr continue
              if m.key != null && m.value != null then
                # attrs element follows
                if m.indent == mNext.indent && !mNext.isListEntry then
                  [ ({ "${m.key}" = m.value; } // next) ]
                # list or unindent follows
                else
                  [ { "${m.key}" = m.value; } ]
              # list begin with only a key (child list/attrs follow)
              else if m.key != null then
                [ { "${m.key}" = childrenMerged; } ]
              # value only (list elem with plain value)
              else
                [ m.value ]
            # not a list entry
            else
            # has key and value
            if m.key != null && m.value != null then
              { "${m.key}" = m.value; }
            # key only
            else
              { "${m.key}" = childrenMerged; };

        in
        result;

    in
    make filtered (-1);
in
parse
