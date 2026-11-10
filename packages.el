;;; packages.el --- Flix layer packages -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kent OHASHI

;; Author: Kent OHASHI <ignorantia.juris.non.excusa@gmail.com>
;; URL: https://github.com/flix/spacemacs
;; License: Apache-2.0

;;; Commentary:

;; Spacemacs layer for the Flix programming language.
;; - Uses flix-mode (https://github.com/flix/emacs) as the major mode.
;; - Starts the official compiler (jar) as the LSP server through flix-mode's
;;   public API.
;; The Flix LSP server loads the whole project on initialize, so no manual
;; file registration is needed.

;;; Code:

(defconst flix-packages
  '(;; The major mode itself.  Requires toml to parse flix.toml.
    (flix-mode :location (recipe
                          :fetcher github
                          :repo "flix/emacs"))
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
    (require 'project)
    ;; Deliberately `add-hook' rather than use-package's `:hook': that keyword
    ;; implies `:defer t', which drops the `require' this form would otherwise
    ;; emit.  flix-mode puts `.flix' into `auto-mode-alist' as a side effect of
    ;; being loaded, and that `add-to-list' carries no autoload cookie, so
    ;; deferring the load leaves .flix files in fundamental-mode.
    (add-hook 'flix-mode-hook #'flix//setup-format-on-save)
    (spacemacs/declare-prefix-for-mode 'flix-mode "m=" "format")
    (spacemacs/declare-prefix-for-mode 'flix-mode "mc" "compile/run")
    (spacemacs/declare-prefix-for-mode 'flix-mode "ms" "repl")
    (spacemacs/declare-prefix-for-mode 'flix-mode "mt" "test")
    (spacemacs/declare-prefix-for-mode 'flix-mode "mT" "toggle")
    ;; `lsp-format-buffer' is already on "=b" from the lsp layer's minor-mode
    ;; bindings; "==" is the major-mode spelling other layers use for
    ;; formatting the whole buffer, so bind it to the same command.
    (spacemacs/set-leader-keys-for-major-mode 'flix-mode
      "'" 'flix/repl
      "==" 'lsp-format-buffer
      "cc" 'flix/run
      "ta" 'flix/test
      "si" 'flix/repl
      "sq" 'flix/repl-quit
      "T=" 'flix/toggle-format-on-save)
    ;; REPL history navigation, following the Python/Haskell layers'
    ;; convention: C-j moves to a newer input, C-k to an older one.
    (define-key flix-repl-mode-map (kbd "C-j") #'comint-next-input)
    (define-key flix-repl-mode-map (kbd "C-k") #'comint-previous-input)))

(defun flix//project-find (dir)
  "Find the enclosing Flix project for DIR by locating flix.toml.
Return a project of the form (transient . ROOT) so that project.el uses
the directory containing flix.toml as the project root.  In a monorepo,
the flix.toml lives in a subdirectory below the VC root, so relying on the
VC (or projectile) root alone points flix-mode at the wrong directory."
  (when-let* ((root (locate-dominating-file dir "flix.toml")))
    (cons 'transient root)))

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
              ;; Make flix.toml the highest-priority project marker in this
              ;; buffer.  A global entry in `project-find-functions' is not
              ;; enough: projectile's own entry is prepended after the layer
              ;; loads and wins, returning the VC root instead of the flix.toml
              ;; directory.  Setting it buffer-locally here keeps flix.toml
              ;; first for .flix buffers without affecting other languages, and
              ;; must run before the jar is resolved below.
              (setq-local project-find-functions
                          (cons #'flix//project-find project-find-functions))
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
