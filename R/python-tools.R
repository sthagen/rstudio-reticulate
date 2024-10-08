
python_has_modules <- function(python, modules) {

  # write code to tempfile
  file <- tempfile("reticulate-python-", fileext = ".py")
  code <- paste("import", modules)
  writeLines(code, con = file)
  on.exit(unlink(file), add = TRUE)

  # invoke Python
  status <- system2(python, shQuote(file), stdout = FALSE, stderr = FALSE)
  status == 0L

}

python_has_module <- function(python, module) {
  code <- paste("import", module)
  args <- c("-E", "-c", shQuote(code))
  status <- system2(python, args, stdout = FALSE, stderr = FALSE)
  status == 0L
}

python_version <- function(python) {
  code <- "import platform; print(platform.python_version())"
  args <- c("-E", "-c", shQuote(code))
  output <- system2(python, args, stdout = TRUE, stderr = FALSE)
  sanitized <- gsub("[^0-9.-]", "", output)
  numeric_version(sanitized)
}

python_module_version <- function(python, module) {
  fmt <- "import %1$s; print(%1$s.__version__)"
  code <- sprintf(fmt, module)
  args <- c("-E", "-c", shQuote(code))
  output <- system2(python, args, stdout = TRUE, stderr = FALSE)
  numeric_version(output)
}

# given the path to a python binary, or an environment path,
# try to find the path to the associated python binary, and
# figure out if it's a virtualenv, conda environment, or none
python_info <- function(path) {

  path <- path.expand(path)
  parent <- dirname(path)

  # NOTE: we check for both 'python' and 'python3' because certain python
  # installations might install one version of the binary but not the other.
  #
  # Some installations might not place Python within a 'Scripts' or 'bin'
  # sub-directory, so look in the root directory too.
  prefixes <- list(NULL, if (is_windows()) "Scripts" else "bin")
  suffixes <- if (is_windows())
    "python.exe"
  else if (startsWith(basename(path), "python3"))
    "python3" # don't resolve 'python' for 'python3'
  else
    c("python", "python3")

  # placeholder for a discovered system python
  systemPython <- NULL

  while (path != parent) {

    # check for virtual environment files
    files <- c(
      "pyvenv.cfg",                                  # created by venv
      file.path(prefixes[[2L]], "activate_this.py")  # created by virtualenv
    )

    paths <- file.path(path, files)
    virtualenv <- any(file.exists(paths))

    # extra check that we aren't in a conda environment
    condapath <- file.path(path, "condabin/conda")
    if (file.exists(condapath))
      virtualenv <- FALSE

    if (virtualenv)
      return(python_info_virtualenv(path))

    # check for conda environment files
    condaenv <- file.exists(file.path(path, "conda-meta"))
    if (condaenv)
      return(python_info_condaenv(path))

    # check for python binary (implies a system install)
    # we don't return immediately here because we might find
    # as we traverse upwards that some of the expected virtualenv
    # or condaenv files exist, so we just save the path and use
    # it later if appropriate
    if (is.null(systemPython)) {
      for (prefix in prefixes) {
        for (suffix in suffixes) {
          bin <- paste(c(path, prefix, suffix), collapse = "/")
          if (file.exists(bin)) {
            systemPython <- bin
            break
          }
        }
      }
    }

    # recurse
    parent <- path
    path <- dirname(path)

  }

  # if we found a system python, use that as the fallback
  if (!is.null(systemPython))
    return(python_info_system(dirname(systemPython), systemPython))

  stopf("could not find a Python environment for %s", path)

}

python_info_virtualenv <- function(path) {

  # form path to python binary
  suffix <- if (is_windows()) "Scripts/python.exe" else "bin/python"
  python <- file.path(path, suffix)

  # return details
  out <- list(
    python = python,
    type = "virtualenv",
    root = path
  )

  if (file.exists(cfg <- file.path(out$root, "pyvenv.cfg"))) {
    starter <- grep("^home = ", readLines(cfg), value = TRUE)
    if(length(starter))
      out$starter <- str_drop_prefix(starter, "home = ")
  }

  out
}

python_info_condaenv <- function(path) {

  # form path to python binary
  suffix <- if (is_windows()) "python.exe" else "bin/python"
  python <- file.path(path, suffix)

  # find path to conda associated with this env
  conda <- get_python_conda_info(python)$conda

  list(
    python = python,
    type   = "conda",
    root   = path,
    conda  = conda
  )

}

python_info_system <- function(path, python) {

  list(
    python = python,
    type   = "system",
    root   = path
  )

}
