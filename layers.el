;;; layers.el --- Flix layer dependencies -*- lexical-binding: t -*-

;; Copyright (C) 2026 Kent OHASHI

;; Author: Kent OHASHI <ignorantia.juris.non.excusa@gmail.com>
;; URL: https://github.com/lagenorhynque/flix-layer
;; License: GPL-3.0-or-later

;;; Commentary:

;; Depends on the lsp layer (to register the Flix LSP client with lsp-mode).
;; The toml package (flix-mode's dependency) is declared in packages.el.

;;; Code:

(configuration-layer/declare-layers '(lsp))
