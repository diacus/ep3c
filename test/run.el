;;; run.el --- Run the EP3C test suite in batch mode -*- lexical-binding: t -*-
;;
;;; Commentary:
;;
;; Run the whole suite non-interactively with:
;;
;;   emacs -Q --batch -l test/run.el
;;
;; Exits 0 when every test passes, 1 otherwise.
;;
;;; Code:

;; Tests assume the repository root as working directory.
(setq default-directory
      (expand-file-name
       ".."
       (file-name-as-directory
        (file-name-directory
         (or load-file-name
             (expand-file-name buffer-file-name default-directory))))))

(require 'ert)

(load-file (expand-file-name "test/ep3c-test.el" default-directory))

(ert-run-tests-batch-and-exit)

;;; run.el ends here