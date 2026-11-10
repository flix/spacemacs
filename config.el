;;; config.el --- Flix layer configuration -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kent OHASHI

;; Author: Kent OHASHI <ignorantia.juris.non.excusa@gmail.com>
;; URL: https://github.com/flix/spacemacs
;; License: Apache-2.0

;;; Commentary:

;; Variables the layer exposes to `dotspacemacs/user-init'.

;;; Code:

(defvar flix-format-on-save nil
  "If non-nil, format a Flix buffer before saving it.  Default is nil.
Formatting goes through the Flix LSP server's `textDocument/formatting',
the same request `SPC m = =' sends.  Toggle it for the running session
with `SPC m T ='.")
