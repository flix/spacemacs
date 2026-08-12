;;; packages.el --- Flix layer packages -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kent OHASHI

;; Author: Kent OHASHI <ignorantia.juris.non.excusa@gmail.com>
;; URL: https://github.com/lagenorhynque/flix-layer
;; License: GPL-3.0-or-later

;;; Commentary:

;; Spacemacs layer for the Flix programming language.
;; - Uses flix-mode (https://codeberg.org/mdiin/flix-mode) as the major mode.
;; - Starts the official compiler (jar) as the LSP server through flix-mode's
;;   public API.
;; The Flix LSP server loads the whole project on initialize, so no manual
;; file registration is needed.

;;; Code:

(defconst flix-packages
  '(;; The major mode itself.  Requires toml to parse flix.toml.
    (flix-mode :location (recipe
                          :fetcher codeberg
                          :repo "mdiin/flix-mode"))
    ;; flix-mode's dependency (require 'toml).  Declared here to pin load order.
    (toml :location (recipe
                     :fetcher github
                     :repo "gongo/emacs-toml"))
    ;; Packages owned by other layers; configured via post-init below.
    lsp-mode
    projectile))

(defun flix/init-toml ()
  "Ensure toml is loaded so flix-mode can require it."
  (use-package toml
    :demand t))

(defun flix/init-flix-mode ()
  "Initialize flix-mode as the major mode and set up key bindings."
  (use-package flix-mode
    :after toml
    :config
    (spacemacs/declare-prefix-for-mode 'flix-mode "mc" "compile/run")
    (spacemacs/declare-prefix-for-mode 'flix-mode "ms" "repl")
    (spacemacs/declare-prefix-for-mode 'flix-mode "mt" "test")
    (spacemacs/set-leader-keys-for-major-mode 'flix-mode
      "'" 'flix/repl
      "cc" 'flix/run
      "ta" 'flix/test
      "si" 'flix/repl
      "sq" 'flix/repl-quit)
    ;; REPL history navigation, following the Python/Haskell layers'
    ;; convention: C-j moves to a newer input, C-k to an older one.
    (define-key flix-repl-mode-map (kbd "C-j") #'comint-next-input)
    (define-key flix-repl-mode-map (kbd "C-k") #'comint-previous-input)))

(defun flix//default-directory-parent-of-root (orig-fn &rest args)
  "Set the server cwd to the parent of the workspace root in flix-mode buffers.
The Flix LSP server resolves the workspaceFolder name as a relative path,
but lsp-mode sends the directory's short name, so unless the cwd is the
parent of the root, the project files are not loaded.  ORIG-FN and ARGS
fall through for every other mode."
  (if (derived-mode-p 'flix-mode)
      (let ((root (lsp-workspace-root)))
        (if root
            (file-name-directory (directory-file-name root))
          (apply orig-fn args)))
    (apply orig-fn args)))

(defun flix/post-init-lsp-mode ()
  "Register the Flix LSP client and start LSP automatically in flix-mode.
The compiler (jar) is launched through flix-mode's public API.  The server
loads every project file (*.flix, src/**, test/**, lib/**) on initialize."
  ;; Register the hook without waiting for lsp-mode (lsp-deferred is autoloaded).
  ;; Opening a .flix file calls lsp-deferred, which loads lsp-mode and thus
  ;; triggers the with-eval-after-load body below.  Semantic tokens
  ;; (server-provided highlighting) must be enabled before LSP starts.
  (add-hook 'flix-mode-hook
            (lambda ()
              (setq-local lsp-semantic-tokens-enable t)
              (lsp-deferred)))
  ;; Client registration must run after lsp-mode is loaded.
  (with-eval-after-load 'lsp-mode
    (add-to-list 'lsp-language-id-configuration '(flix-mode . "flix"))
    (advice-add 'lsp--default-directory-for-connection :around
                #'flix//default-directory-parent-of-root)
    (lsp-register-client
     (make-lsp-client
      :new-connection (lsp-stdio-connection #'flix/lsp-command)
      :activation-fn (lsp-activate-on "flix")
      :server-id 'flix-ls
      :priority 0
      ;; The server does not implement workspace/executeCommand, so handle the
      ;; "Run" code lens (flix.runMain) on the client side via the REPL.
      :action-handlers (ht ("flix.runMain" #'flix//lsp-action-run-main))))))

(defun flix/post-init-projectile ()
  "Use flix.toml as a project root marker."
  (with-eval-after-load 'projectile
    (add-to-list 'projectile-project-root-files "flix.toml")))
