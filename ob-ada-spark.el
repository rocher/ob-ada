;;; ob-ada-spark.el --- Babel functions for Ada & SPARK

;; Copyright (C) 2021 Francesc Rocher

;; Author: Francesc Rocher
;; Keywords: literate programming, reproducible research
;; Homepage: https://orgmode.org

;; This file is NOT YET part of GNU Emacs.

;; ob-ada-spark is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; ob-ada-spark is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with ob-ada-spark. If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Org-Babel support for evaluating Ada & SPARK code and proving SPARK code.
;;
;; Very limited implementation.

;;; Requirements:

;; * An Ada compiler (gnatmake)
;; * A SPARK formal verification tool (gnatprove)
;; * Emacs ada-mode, optional but strongly recommended, see
;;   <https://www.nongnu.org/ada-mode/>

;;; Code:
(require 'ob)

(defvar org-babel-tangle-lang-exts)
(add-to-list 'org-babel-tangle-lang-exts '("ada" . "adb"))

(defcustom org-babel-ada-spark-compile-cmd "gnatmake"
  "Command used to compile Ada/SPARK code into an executable.
May be either a command in the path, like gnatmake, or an
absolute path name, like /opt/ada/bin/gnatmake.
Parameter may be used, like gnatmake -we. If you specify here an
Ada version flag, like -gnat95, then this value can conflict with
the :ada-version variable specified in an Ada block."
  :group 'org-babel
  :type 'string)

(defcustom org-babel-ada-spark-prove-cmd "gnatprove --output=pretty --report=all"
  "Command used to prove SPARK code.
May be either a command in the path, like gnatprove, or an
absolute path name, like /opt/ada/bin/gnatprove.
Parameter may be used, like gnatprove --prover=z3."
  :group 'org-babel
  :type 'string)

(defcustom org-babel-ada-spark-compiler-enable-assertions "-gnata"
  "Ada compiler flag to enable assertions.
Used when the :assertions variable is set to t in an Ada block."
  :group 'org-babel
  :type 'string)

(defcustom org-babel-ada-spark-version 2012
  "Language version to evaluate Ada/SPARK blocks.
Works with the GNAT compiler and gnatmake command. If using a
different compiler, then select 'default' here and specify version
flags in the `org-babel-ada-spark-compile-cmd' variable."
  :group 'org-babel
  :type '(choice
          (const :tag "default" 0)
          (const :tag "Ada 83" 83)
          (const :tag "Ada 95" 95)
          (const :tag "Ada 2005" 2005)
          (const :tag "Ada 2012" 2012)
          (const :tag "Ada 2022" 2022)))

(defvar org-babel-ada-spark-temp-file-counter 0
  "Internal counter to generate sequential Ada/SPARK unit names.")

(defun org-babel-ada-spark-temp-file (prefix suffix &optional unit no-suffix)
  "Create a temporary file with a name compatible with Ada/SPARK."
  (let* ((temp-file-directory
          (if (file-remote-p default-directory)
              (concat (file-remote-p default-directory)
                      org-babel-remote-temporary-directory)
            (or (and (boundp 'org-babel-temporary-directory)
                     (file-exists-p org-babel-temporary-directory)
                     org-babel-temporary-directory)
                temporary-file-directory)))
         (temp-file-name
          (if (stringp unit)
              (if no-suffix unit (concat unit suffix))
            (format "%s%06d%s"
                    prefix
                    (setq org-babel-ada-spark-temp-file-counter
                          (1+ org-babel-ada-spark-temp-file-counter))
                    suffix)))
         (file-name (file-name-concat temp-file-directory temp-file-name)))
    (f-touch (file-name-concat temp-file-directory temp-file-name))
    file-name))

(defun org-babel-expand-body:ada (body params &optional processed-params)
  "Expand BODY according to PARAMS, return the expanded body."
    body)

(defun org-babel-execute:ada (body params)
  "Execute a block of Ada code with org-babel.
This function is called by `org-babel-execute-src-block'"
  (message "executing Ada source code block")
  (let* ((processed-params (org-babel-process-params params))
         (ada-version (or (cdr (assq :ada-version processed-params)) 0))
         (unit (cdr (assq :unit processed-params)))
         (assertions (cdr (assq :assertions processed-params)))
         (prove (cdr (assq :prove processed-params)))
         (mode  (cdr (assq :mode processed-params)))
         (level  (cdr (assq :level processed-params)))
         (full-body (org-babel-expand-body:ada
                     body params processed-params))
         (temp-src-file
          (org-babel-ada-spark-temp-file "ada-src" ".adb" unit)))
    (with-temp-file temp-src-file (insert full-body))
    (if (string-equal prove "t")
        ;; prove SPARK code
        (let* ((temp-gpr-file
                (org-babel-ada-spark-temp-file "spark_p" ".gpr" unit))
               (temp-project (file-name-base temp-gpr-file)))
          (with-temp-file temp-gpr-file
            (insert (format "project %s is
  for Source_Files use (\"%s\");
  for Main use (\"%s\");
end %s;
"
                            temp-project
                            (file-name-nondirectory temp-src-file)
                            temp-src-file
                            temp-project)))
          (when-let ((gnatprove-directory
                      (file-name-concat
                       org-babel-temporary-directory "gnatprove"))
                     (exists-gnatprove-directory
                      (file-exists-p gnatprove-directory)))
            (delete-directory gnatprove-directory t))
          (org-babel-eval
           (format "%s -P%s %s %s -u %s"
                   org-babel-ada-spark-prove-cmd
                   temp-gpr-file
                   (if (stringp mode) (concat "--mode=" mode) "")
                   (if (stringp level) (concat "--level=" level) "")
                   temp-src-file) ""))
      ;; evaluate Ada/SPARK code
      (let ((default-directory org-babel-temporary-directory)
            (temp-bin-file
             (org-babel-ada-spark-temp-file "ada-bin" "" unit t)))
        (if (stringp unit)
            (cl-mapcar
             (lambda (ext)
               (let ((file (file-name-concat org-babel-temporary-directory (concat unit ext))))
                 (when (file-exists-p file) (delete-file file))))
             '("" ".ali" ".o")))
        (org-babel-eval
         (format "%s %s %s -o %s %s"
                 org-babel-ada-spark-compile-cmd
                 (if (> (+ ada-version org-babel-ada-spark-version) 0)
                     (format "-gnat%d" (if (> ada-version 0) ada-version org-babel-ada-spark-version))
                   "")
                 (if (string-equal assertions "t")
                     org-babel-ada-spark-compiler-enable-assertions
                   "")
                 temp-bin-file
                 temp-src-file) "")
        (org-babel-eval temp-bin-file "")))))

(defun org-babel-prep-session:ada-spark (session params)
  "This function does nothing as Ada and SPARK are compiled
languages with no support for sessions."
  (error "Ada & SPARK are compiled languages -- no support for sessions"))

(defun org-babel-ada-spark-table-or-string (results)
  "If the results look like a table, then convert them into an
Emacs-lisp table, otherwise return the results as a string."
  results)

(provide 'ob-ada-spark)

;;; ob-ada-spark.el ends here
