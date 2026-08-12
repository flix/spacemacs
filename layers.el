;;; layers.el --- Flix layer dependencies -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kent OHASHI

;; Author: Kent OHASHI <ignorantia.juris.non.excusa@gmail.com>
;; URL: https://github.com/flix/spacemacs
;; License: Apache-2.0

;;; Commentary:

;; Depends on the lsp layer (to register the Flix LSP client with lsp-mode).
;; The toml package (flix-mode's dependency) is declared in packages.el.

;;; Code:

(configuration-layer/declare-layers '(lsp))
