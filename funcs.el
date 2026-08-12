;;; funcs.el --- Flix layer functions -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kent OHASHI

;; Author: Kent OHASHI <ignorantia.juris.non.excusa@gmail.com>
;; URL: https://github.com/lagenorhynque/flix-layer
;; License: GPL-3.0-or-later

;;; Commentary:

;; Glue functions bridging flix-mode's public API to lsp-mode and the
;; Spacemacs key-binding system.

;;; Code:

(defun flix//compiler-command ()
  "Return the Flix compiler invocation as a list of strings.
Delegates to flix-mode, which downloads the jar on demand and resolves
its version from flix.toml.  The result looks like
\(\"java\" \"-jar\" <jar> \"lsp\")."
  (flix-mode-ensure)
  (flix-mode-server-path nil))

(defun flix//command-with-subcommand (subcommand)
  "Return the compiler command with its trailing subcommand replaced by SUBCOMMAND.
`flix//compiler-command' ends with \"lsp\"; this swaps that for e.g.
\"run\", \"test\", or \"repl\"."
  (append (butlast (flix//compiler-command)) (list subcommand)))

(defun flix/lsp-command (&rest _)
  "Return the command that launches the Flix LSP server.
Suitable as the COMMAND argument of `lsp-stdio-connection'."
  (flix//compiler-command))

(defun flix//run-subcommand (subcommand)
  "Run the Flix CLI SUBCOMMAND for the current project.
Reuse the jar resolved by flix-mode and run from the project root."
  (let ((default-directory (project-root (project-current))))
    (compile (mapconcat #'shell-quote-argument
                        (flix//command-with-subcommand subcommand)
                        " "))))

(defun flix/run ()
  "Run `flix run' for the current project."
  (interactive)
  (flix//run-subcommand "run"))

(defun flix/test ()
  "Run `flix test' for the current project."
  (interactive)
  (flix//run-subcommand "test"))

;;; REPL

(defconst flix--repl-prompt-regexp "flix> "
  "Regexp matching the Flix REPL prompt.")

(defconst flix--repl-font-lock-keywords
  (let ((keywords '("def" "pub" "let" "if" "else" "match" "case" "type"
                    "enum" "struct" "trait" "instance" "import" "use" "mod"
                    "law" "sealed" "with" "without" "as" "forall" "for"
                    "foreach" "yield" "do" "try" "catch" "throw" "spawn"
                    "par" "region" "new" "eff" "lazy" "force" "discard"
                    "and" "or" "not" "select" "from" "into" "where" "query"
                    "solve" "inject" "project" "ref" "deref"))
        (types '("Unit" "Bool" "Char" "Float32" "Float64" "BigDecimal"
                 "Int8" "Int16" "Int32" "Int64" "BigInt" "String"))
        (constants '("true" "false")))
    `((,(regexp-opt keywords 'symbols) . font-lock-keyword-face)
      (,(regexp-opt types 'symbols) . font-lock-type-face)
      (,(regexp-opt constants 'symbols) . font-lock-constant-face)))
  "Minimal font-lock keywords for the Flix REPL.
flix-mode itself carries no font-lock rules -- it relies entirely on the
LSP server's semantic tokens, which are unavailable in the REPL buffer --
so these give the REPL a small amount of standalone highlighting.")

(define-derived-mode flix-repl-mode comint-mode "Flix-REPL"
  "Major mode for the Flix REPL buffer.
Derives from `comint-mode' so the standard input ring and editing
commands are available.  Key bindings are set in `packages.el'."
  (setq-local comint-prompt-regexp flix--repl-prompt-regexp)
  ;; Keep submitted input syntax-highlighted: `comint-send-input' otherwise
  ;; overwrites it with `comint-highlight-input' (bold) and marks it as
  ;; non-refontifiable, wiping the per-token colors.  We trade comint's bold
  ;; styling of past input for persistent highlighting.
  (setq-local comint-highlight-input nil)
  ;; C-style comments; strings inherit the standard double-quote syntax.
  (modify-syntax-entry ?/ ". 124b")
  (modify-syntax-entry ?* ". 23")
  (modify-syntax-entry ?\n "> b")
  (setq-local font-lock-defaults '(flix--repl-font-lock-keywords)))

(defun flix//repl-live-buffer (root)
  "Return the live Flix REPL buffer for ROOT, or nil if none is running."
  (let ((buffer (get-buffer (format "*flix-repl: %s*" (abbreviate-file-name root)))))
    (and buffer (comint-check-proc buffer) buffer)))

(defun flix//repl-start (root)
  "Start a Flix REPL for ROOT and return its buffer.
The REPL runs from ROOT so it picks up the project's flix.toml."
  (let* ((default-directory root)
         (process-name (format "flix-repl: %s" (abbreviate-file-name root)))
         (command (flix//command-with-subcommand "repl"))
         (buffer (apply #'make-comint-in-buffer
                        process-name (format "*%s*" process-name)
                        (car command) nil (cdr command))))
    (with-current-buffer buffer
      (unless (derived-mode-p 'flix-repl-mode)
        (flix-repl-mode)))
    buffer))

(defun flix//repl-buffer (root)
  "Return a live Flix REPL buffer for ROOT, starting one if necessary."
  (or (flix//repl-live-buffer root)
      (flix//repl-start root)))

(defun flix/repl ()
  "Start or switch to the Flix REPL for the current project."
  (interactive)
  (pop-to-buffer (flix//repl-buffer (project-root (project-current)))))

(defun flix/repl-quit ()
  "Quit the Flix REPL for the current project, if one is running."
  (interactive)
  (let ((buffer (flix//repl-live-buffer (project-root (project-current)))))
    (if buffer
        (flix//repl-send buffer ":quit")
      (message "No Flix REPL is running for this project."))))

(defun flix//repl-send (buffer string)
  "Send STRING as a line of input to the Flix REPL in BUFFER."
  (comint-send-string buffer (concat string "\n")))

(defun flix//repl-send-when-ready (buffer string)
  "Send STRING to BUFFER once its REPL prompt appears.
Used after starting a REPL, whose dependency resolution delays the first
prompt; sending too early yields a parse error."
  (with-current-buffer buffer
    (letrec ((filter
              (lambda (output)
                (when (string-match-p flix--repl-prompt-regexp output)
                  (remove-hook 'comint-output-filter-functions filter t)
                  (flix//repl-send buffer string)))))
      (add-hook 'comint-output-filter-functions filter nil t))))

(defun flix//repl-eval (expression)
  "Send EXPRESSION to the current project's Flix REPL via `:eval'.
If the REPL must be started first, wait for its prompt before sending."
  (let* ((root (project-root (project-current)))
         (live (flix//repl-live-buffer root))
         (buffer (or live (flix//repl-start root)))
         (input (format ":eval %s" expression)))
    (if live
        (flix//repl-send buffer input)
      (flix//repl-send-when-ready buffer input))
    (pop-to-buffer buffer)))

(defun flix//run-main (symbol)
  "Run the entry point named SYMBOL (a fully-qualified name) in the Flix REPL."
  (flix//repl-eval (format "%s()" symbol)))

(defun flix//lsp-action-run-main (action)
  "Handle the `flix.runMain' code lens ACTION.
The Flix LSP server does not implement `workspace/executeCommand', so
this runs the entry point locally through the REPL instead.  The command
argument is a JSON object of the form {\"s\": <fully-qualified-name>},
which lsp-mode parses into a hash table."
  (let ((argument (seq-elt (lsp:command-arguments? action) 0)))
    (flix//run-main (gethash "s" argument))))
