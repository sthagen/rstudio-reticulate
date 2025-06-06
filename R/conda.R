
#' Conda Tools
#'
#' Tools for managing Python `conda` environments.
#'
#' @param envname The name of, or path to, a conda environment.
#'
#' @param conda The path to a `conda` executable. Use `"auto"` to allow
#'   `reticulate` to automatically find an appropriate `conda` binary.
#'   See **Finding Conda** and [conda_binary()] for more details.
#'
#' @param forge Boolean; include the [conda-forge](https://conda-forge.org/)
#'   repository?
#'
#' @param channel An optional character vector of conda channels to include.
#'   When specified, the `forge` argument is ignored. If you need to
#'   specify multiple channels, including the conda forge, you can use
#'   `c("conda-forge", <other channels>)`.
#'
#' @param packages A character vector, indicating package names which should be
#'   installed or removed. Use  \verb{<package>==<version>} to request the installation
#'   of a specific version of a package. A `NULL` value for [conda_remove()]
#'   will be interpretted to `"--all"`, removing the entire environment.
#'
#' @param environment The path to an environment definition, generated via
#'   (for example) [conda_export()], or via `conda env export`. When provided,
#'   the conda environment will be created using this environment definition,
#'   and other arguments will be ignored.
#'
#' @param python_version The version of Python to be used in this conda
#'   environment. The associated Python package from conda will be requested
#'   as `python={python_version}`. When `NULL`, the default `python` package
#'   will be used instead. For example, use `python_version = "3.6"` to request
#'   that the conda environment be created with a copy of Python 3.6. This
#'   argument will be ignored if `python` is specified as part of the `packages`
#'   argument, for backwards compatibility.
#'
#' @param file The path where the conda environment definition will be written.
#'
#' @param json Boolean; should the environment definition be written as JSON?
#'   By default, conda exports environments as YAML.
#'
#' @param pip Boolean; use `pip` for package installation? By default, packages
#'   are installed from the active conda channels.
#'
#' @param pip_ignore_installed Ignore already-installed versions when using pip?
#'   (defaults to `FALSE`). Set this to `TRUE` so that specific package versions
#'   can be installed even if they are downgrades. The `FALSE` option is useful
#'   for situations where you don't want a pip install to attempt an overwrite of
#'   a conda binary package (e.g. SciPy on Windows which is very difficult to
#'   install via pip due to compilation requirements).
#'
#' @param pip_options An optional character vector of additional command line
#'   arguments to be passed to `pip`. Only relevant when `pip = TRUE`.
#'
#' @param python_version The version of Python to be installed. Set this if
#'   you'd like to change the version of Python associated with a particular
#'   conda environment.
#'
#' @param clone The name of the conda environment to be cloned.
#'
#' @param all Boolean; report all instances of Python found?
#'
#' @param additional_create_args An optional character vector of additional
#'   arguments to use in the call to `conda create`.
#'
#' @param additional_install_args An optional character vector of additional
#'   arguments to use in the call to `conda install`.
#'
#' @param ... Optional arguments, reserved for future expansion.
#'
#'
#' @section Finding Conda:
#'
#' Most of `reticulate`'s conda APIs accept a `conda` parameter, used to control
#' the `conda` binary used in their operation. When `conda = "auto"`,
#' `reticulate` will attempt to automatically find a conda installation.
#' The following locations are searched, in order:
#'
#' 1. The location specified by the `reticulate.conda_binary` \R option,
#' 2. The location specified by the `RETICULATE_CONDA` environment variable,
#' 3. The [miniconda_path()] location (if it exists),
#' 4. The program `PATH`,
#' 5. A set of pre-defined locations where conda is typically installed.
#'
#' To force `reticulate` to use a particular `conda` binary, we recommend
#' setting:
#'
#' ```r
#' options(reticulate.conda_binary = "/path/to/conda")
#' ```
#'
#' This can be useful if your conda installation lives in a location that
#' `reticulate` is unable to automatically discover.
#'
#' @name conda-tools
#' @seealso [conda_run2()]
NULL


#' @returns
#'   `conda_list()` returns an \R `data.frame`, with `name` giving the name of
#'   the associated environment, and `python` giving the path to the Python
#'   binary associated with that environment.
#'
#' @rdname conda-tools
#' @export
conda_list <- function(conda = "auto") {

  # resolve conda binary
  conda <- conda_binary(conda)
  local_conda_paths(conda)

  if (startsWith(basename(conda), "micromamba")) {
    conda_envs <- system2(conda, c("env", "list", "--json"),
                          stdout = TRUE, stderr = FALSE)

  } else {
  # list envs -- discard stderr as Anaconda may emit warnings that can
  # otherwise be ignored; see e.g. https://github.com/rstudio/reticulate/issues/474
    conda_envs <- suppressWarnings(
      system2(conda, args = c("info", "--json"),
              stdout = TRUE, stderr = FALSE)
    )
  }

  # check for error
  status <- attr(conda_envs, "status") %||% 0L
  if (status != 0L) {

    # show warning if conda_diagnostics are enabled
    if (getOption("reticulate.conda_diagnostics", default = FALSE)) {
      errmsg <- attr(status, "errmsg")
      warning("Error ", status, " occurred running ", conda, " ", errmsg)
    }

    # return empty data frame
    return(data.frame(
      name = character(),
      python = character(),
      stringsAsFactors = FALSE)
    )

  }

  # strip out anaconda cloud prefix (not valid json)
  if (length(conda_envs) > 0 && grepl("Anaconda Cloud", conda_envs[[1]], fixed = TRUE))
    conda_envs <- conda_envs[-1]

  # parse conda info
  info <- fromJSON(conda_envs)

  # convert to json
  conda_envs <- info$envs

  # normalize and remove duplicates (seems necessary on Windows as Anaconda
  # may report both short-path and long-path versions of the same environment)
  conda_envs <- unique(normalizePath(conda_envs, mustWork = FALSE))

  # return an empty data.frame when no envs are found
  if (length(conda_envs) == 0L) {
    return(data.frame(
      name = character(),
      python = character(),
      stringsAsFactors = FALSE)
    )
  }

  # build data frame
  name <- basename(conda_envs)

  suffix <- if (is_windows()) "python.exe" else "bin/python"
  python <- paste(conda_envs, suffix, sep = "/")

  # handle base environment specially
  # (compare normalized paths for Windows's sake)
  prefix <- info$root_prefix %||% ""
  isbase <-
    normalizePath(prefix, winslash = "/", mustWork = FALSE) ==
    normalizePath(conda_envs, winslash = "/", mustWork = FALSE)

  name[isbase] <- "base"

  data.frame(
    name = name,
    python = python,
    stringsAsFactors = FALSE
  )

}

#' @returns
#'   `conda_create()` returns the path to the Python binary associated with the
#'   newly-created conda environment.
#'
#' @rdname conda-tools
#' @export
conda_create <- function(envname = NULL,
                         packages = NULL,
                         ...,
                         forge = TRUE,
                         channel = character(),
                         environment = NULL,
                         conda = "auto",
                         python_version = miniconda_python_version(),
                         additional_create_args = character())
{
  check_forbidden_install("Conda Environments")

  # resolve conda binary
  conda <- conda_binary(conda)
  local_conda_paths(conda)

  # if environment is provided, use it directly
  if (!is.null(environment))
    return(conda_create_env(envname, environment, conda, additional_create_args))

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # resolve packages argument
  if (!any(grepl("^python", packages))) {

    python_package <- if (is.null(python_version))
      "python"
    else
      sprintf("python=%s", python_version)

    packages <- c(python_package, packages)

  }

  # create the environment
  args <- conda_args("create", envname, packages)

  # be quiet
  args <- c(args, "--quiet")

  # add user-requested channels
  channels <- if (length(channel))
    channel
  else if (forge)
    "conda-forge"

  for (ch in channels)
    args <- c(args, "-c", ch)

  # add additional arguments
  args <- c(args, additional_create_args)

  # invoke conda
  result <- system2t(conda, maybe_shQuote(args))
  if (result != 0L) {
    fmt <- "Error creating conda environment '%s' [exit code %i]"
    stopf(fmt, envname, result, call. = FALSE)
  }

  # return the path to the python binary
  conda_python(envname = envname, conda = conda)
}

conda_create_env <- function(envname, environment, conda, additional_create_args) {

  check_forbidden_install("Conda Environments")

  if (!is.null(envname))
    envname <- condaenv_resolve(envname)

  args <- c(
    "env", "create", "--quiet",
    if (is.null(envname))
      c()
    else if (grepl("/", envname))
      c("--prefix", maybe_shQuote(envname))
    else
      c("--name", maybe_shQuote(envname)),
    "-f", maybe_shQuote(environment),
    additional_create_args
  )

  result <- system2t(conda, args)
  if (result != 0L) {
    fmt <- "Error creating conda environment [exit code %i]"
    stopf(fmt, result)
  }

  # return the path to the python binary
  conda_python(envname = envname, conda = conda)

}

#' @returns
#'   `conda_clone()` returns the path to Python within the newly-created
#'   conda environment.
#'
#' @rdname conda-tools
#' @export
conda_clone <- function(envname, ..., clone = "base", conda = "auto") {

  # resolve conda binary
  conda <- conda_binary(conda)
  local_conda_paths(conda)

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # create the environment
  args <- conda_args("create", envname)

  # be quiet
  args <- c(args, "--quiet")

  # add cloned environment
  args <- c(args, "--clone", clone)

  # invoke conda
  result <- system2t(conda, maybe_shQuote(args))
  if (result != 0L) {
    fmt <- "Error creating conda environment '%s' [exit code %i]"
    stopf(fmt, envname, result, call. = FALSE)
  }

  # return the path to the python binary
  conda_python(envname = envname, conda = conda)

}

#' @returns
#'   `conda_export()` returns the path to the exported environment definition,
#'   invisibly.
#'
#' @rdname conda-tools
#' @export
conda_export <- function(envname,
                         file = if (json) "environment.json" else "environment.yml",
                         json = FALSE,
                         ...,
                         conda = "auto")
{
  # resolve parameters
  conda <- conda_binary(conda)
  local_conda_paths(conda)
  envname <- condaenv_resolve(envname)

  # build conda argument list,
  args <- c(
    "env", "export",
    if (json)
      "--json",
    if (grepl("/", envname))
      c("--prefix", shQuote(envname))
    else
      c("--name", shQuote(envname)),
    ">", shQuote(file)
  )

  # execute conda
  status <- system2(conda, args)
  if (status != 0L) {
    fmt <- "Error exporting conda environment [error code %i]"
    stopf(fmt, status, call. = FALSE)
  }

  # notify user
  fmt <- "* Environment '%s' exported to '%s'."
  writeLines(sprintf(fmt, envname, file))

  # return path to generated environment
  invisible(file)
}

#' @rdname conda-tools
#' @export
conda_remove <- function(envname,
                         packages = NULL,
                         conda = "auto")
{
  # resolve conda binary
  conda <- conda_binary(conda)
  local_conda_paths(conda)

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # no packages means everything
  if (is.null(packages))
    packages <- "--all"

  # remove packages (or the entire environment)
  args <- conda_args("remove", envname, packages)
  result <- system2t(conda, maybe_shQuote(args))
  if (result != 0L) {
    stop("Error ", result, " occurred removing conda environment ", envname,
         call. = FALSE)
  }
}

#' @rdname conda-tools
#' @export
conda_install <- function(envname = NULL,
                          packages,
                          forge = TRUE,
                          channel = character(),
                          pip = FALSE,
                          pip_options = character(),
                          pip_ignore_installed = FALSE,
                          conda = "auto",
                          python_version = NULL,
                          additional_create_args = character(),
                          additional_install_args = character(),
                          ...)
{
  check_forbidden_install("Python packages")

  # check that 'packages' argument was supplied
  if (missing(packages)) {
    if (!is.null(envname)) {

      fmt <- paste(
        "argument \"packages\" is missing, with no default",
        "- did you mean 'conda_install(<envname>, %1$s)'?",
        "- use 'py_install(%1$s)' to install into the active Python environment",
        sep = "\n"
      )

      stopf(fmt, deparse1(substitute(envname)), call. = FALSE)
    } else {
      packages
    }
  }

  # resolve conda binary
  conda <- conda_binary(conda)
  local_conda_paths(conda)

  # resolve environment name
  envname <- condaenv_resolve(envname)

  # honor request for specific version of Python package
  python_package <- if (is.null(python_version))
    NULL
  else if (grepl("[><=]", python_version))
    paste0("python", python_version)
  else
    sprintf("python=%s", python_version)

  # check to see if we already have a valid Python installation for
  # this conda environment
  python <- tryCatch(
    conda_python(envname = envname, conda = conda),
    error = identity
  )

  # if this conda environment doesn't seem to exist, auto-create it
  if (inherits(python, "error") || !file.exists(python)) {

    conda_create(
      envname = envname,
      packages = python_package %||% "python",
      forge = forge,
      channel = channel,
      conda = conda,
      additional_create_args = additional_create_args
    )

    python <- conda_python(envname = envname, conda = conda)

  }

  # prepare user-requested channels
  channels <- if (length(channel))
    channel
  else if (forge)
    "conda-forge"

  channel_args <- character()
  for (ch in channels)
    channel_args <- c(channel_args, "-c", ch)

  # if the user has requested a specific version of Python, ensure that
  # version of Python is installed into the requested environment
  # (should be no-op if that copy of Python already installed)
  if (!is.null(python_version)) {
    args <- conda_args("install", envname, python_package)
    args <- c(args, channel_args, additional_install_args)
    status <- system2t(conda, maybe_shQuote(args))
    if (status != 0L) {
      fmt <- "installation of '%s' into environment '%s' failed [error code %i]"
      msg <- sprintf(fmt, python_package, envname, status)
      stop(msg, call. = FALSE)
    }
  }

  # delegate to pip if requested
  if (pip) {

    result <- pip_install(
      python = python,
      packages = packages,
      pip_options = pip_options,
      ignore_installed = pip_ignore_installed,
      conda = conda,
      envname = envname
    )

    return(result)

  }

  # otherwise, use conda
  args <- conda_args("install", envname)

  # add user-requested channels
  args <- c(args, channel_args)

  args <- c(args, python_package, packages, additional_install_args)
  result <- system2t(conda, maybe_shQuote(args))

  # check for errors
  if (result != 0L) {
    fmt <- "one or more Python packages failed to install [error code %i]"
    stopf(fmt, result)
  }


  invisible(packages)
}

#' @rdname conda-tools
#' @export
conda_binary <- function(conda = "auto") {

  # automatic lookup if requested
  if (identical(conda, "auto") || isTRUE(is.na(conda))) {
    conda <- find_conda()
    if (is.null(conda))
      stop("Unable to find conda binary. Is Anaconda installed?", call. = FALSE)
    conda <- conda[[1]]
  }

  conda <- normalizePath(conda, winslash = "/", mustWork = FALSE)
  if (!grepl("^(conda|mamba|micromamba)", basename(conda)))
    warning("Supplied path is not a conda binary: ", sQuote(conda))

  # if the user has requested a conda binary in the 'condabin' folder,
  # try to find and use its sibling in the 'bin' folder instead as
  # we rely on other tools typically bundled in the 'bin' folder
  # https://github.com/rstudio/keras/issues/691
  if (!is_windows()) {
    altpath <- file.path(dirname(conda), "../bin", basename(conda))
    if (file.exists(altpath))
      return(normalizePath(altpath, winslash = "/", mustWork = TRUE))
  } else {
    # on Windows it's preferable to conda.bat located in the 'condabin'
    # folder. if the user passed the path to a 'Scripts/conda.exe' we will
    # try to find the 'conda.bat'.
    altpath <- file.path(dirname(conda), "../condabin/conda.bat")
    if (file.exists(altpath))
      return(normalizePath(altpath, winslash = "/", mustWork = TRUE))
  }

  # validate existence
  if (!file.exists(conda))
    stop("Specified conda binary '", conda, "' does not exist.", call. = FALSE)

  # return conda
  conda
}

#' @rdname conda-tools
#' @export
conda_exe <- conda_binary


#' @rdname conda-tools
#' @export
conda_version <- function(conda = "auto") {
  conda_bin <- conda_binary(conda)
  local_conda_paths(conda_bin)
  out <- system2(conda_bin, "--version", stdout = TRUE)

  # mamba --version gives multi-line output, with the conda version on the last line.
  tail(out, 1)
}


#' @rdname conda-tools
#' @export
conda_update <- function(conda = "auto") {

  # resolve conda
  conda <- conda_binary(conda)
  local_conda_paths(conda)

  # compute base path
  prefix <- system2(conda, c("info", "--base"), stdout = TRUE)

  # figure out if this is anaconda or 'plain' conda
  json <- system2(conda, c("list", "--prefix", shQuote(prefix), "--json"), stdout = TRUE)
  envlist <- jsonlite::fromJSON(json)
  name <- if ("anaconda" %in% envlist$name) "anaconda" else "conda"

  # attempt update
  system2t(conda, c("update", "--prefix", maybe_shQuote(prefix), "--yes", name))
}

numeric_conda_version <- function(conda = "auto", version_string = conda_version(conda)) {
  # some plausible version strings:
  # "conda 4.6.0"
  # "conda 4.6.0b0"
  # "conda 4.6.0rc1"
  # "conda 4.6.0rc1.post3+64bde06"
  v <- version_string
  v <- sub("^conda ", "", v) # drop hardcoded prefix

  # https://github.com/conda/conda/blob/c1579681d1468af3d1b4af3083bed33f8391e861/conda/_vendor/auxlib/packaging.py#L142
  # if dev version string: "{0}.post{1}+{2}".format(version, post_commit, hash)
  v <- sub("\\.post(\\d)\\+.+$", ".\\1", v)

  # substitute rc|beta|alpha|whatever suffix with .
  v <- sub("[A-Za-z]+", ".", v)

  if (grepl("\\.$", v))
    v <- paste0(v, "9000")

  numeric_version(v)
}


#' @rdname conda-tools
#' @export
conda_python <- function(envname = NULL,
                         conda = "auto",
                         all = FALSE)
{
  # resolve envname
  envname <- condaenv_resolve(envname)

  # for fully-qualified paths, construct path explicitly
  if (grepl("[/\\\\]", envname)) {
    suffix <- if (is_windows()) "python.exe" else "bin/python"
    path <- file.path(envname, suffix)
    if (file.exists(path))
      return(path)

    fmt <- "no conda environment exists at path '%s'"
    stop(sprintf(fmt, envname))
  }

  # otherwise, list conda environments and try to find it
  conda_envs <- conda_list(conda = conda)
  env <- subset(conda_envs, conda_envs$name == envname)
  if (nrow(env) == 0)
    stop("conda environment '", envname, "' not found")

  # NOTE: it's possible to have multiple environments with the same name;
  # e.g. because the user might've installed multiple copies of Anaconda
  # (e.g. both miniconda and miniforge). we should think about having a way
  # of disambiguating this, but for now just pick the first one
  python <- if (all) env$python else env$python[[1L]]
  path.expand(python)
}

#' @returns
#'   `conda_search()` returns an \R `data.frame` describing packages that
#'   matched against `matchspec`. The data frame will usually include
#'   fields `name` giving the package name, `version` giving the package
#'   version, `build` giving the package build, and `channel` giving the
#'   channel the package is hosted on.
#'
#' @param matchspec A conda MatchSpec query string.
#'
#' @rdname conda-tools
#' @export
conda_search <-
  function(matchspec,
           forge = TRUE,
           channel = character(),
           conda = "auto",
           ...) {

  conda <- conda_binary(conda)
  local_conda_paths(conda)

  args <- c("search", matchspec)

  # add user-requested channels
  channels <- if (length(channel))
    channel
  else if (forge)
    "conda-forge"

  for (ch in channels)
    args <- c(args, "-c", ch)

  args = c(args, "--json")
  output <- system2(conda, shQuote(args), stdout = TRUE)
  status <- attr(output, "status") %||% 0L
  # check for errors
  if (status != 0L) {
    fmt <- "error searching for packages [error code %i]"
    stopf(fmt, status)
  }

  parsed <- jsonlite::fromJSON(output)

  all_colnames <- unique(unlist(lapply(parsed, names)))
  df <- do.call(rbind, lapply(parsed, function(x) {
    if(any(missing_cols <- setdiff(all_colnames, names(x))))
      x[missing_cols] <- NA
    x
  }))
  rownames(df) <- NULL

  # reverse row order, so most recent versions are (likely) first. In an ideal
  # world we'd use `order(numeric_version(df$version))`, but we can't depend on
  # the version string being parseable.
  if(nrow(df))
    df <- df[rev(seq_len(nrow(df))), ]

  # reorder columns
  to_front <- intersect(c("name", "version", "build", "channel"), names(df))
  df <- df[c(unique(to_front, names(df)))]

  df
}


find_conda <- function() {

  # allow specification of conda executable
  conda <- getOption("reticulate.conda_binary")
  if (!is.null(conda))
    return(conda)

  conda <- Sys.getenv("RETICULATE_CONDA", unset = NA)
  if (!is.na(conda))
    return(conda)

  # if miniconda is installed, use it
  if (miniconda_exists())
    return(miniconda_conda())

  # The preferred order of conda environment managers is
  # micromamba (fastest)
  # mamba (fast)
  # conda (slow)

  # if there is a micromamba executable on the PATH, use it
  conda <- Sys.which("micromamba")
  if (nzchar(conda))
    return(conda)

  # if there is a mamba executable on the PATH, use it
  conda <- Sys.which("mamba")
  if (nzchar(conda))
    return(conda)

  # if there is a conda executable on the PATH, use it
  conda <- Sys.which("conda")
  if (nzchar(conda))
    return(conda)

  # otherwise, search common locations for conda
  prefixes <- c("~/opt/", "~/", "/opt/", "/")
  names <- c("anaconda", "miniconda", "miniforge")
  versions <- c("", "2", "3", "4")
  combos <- expand.grid(versions, names, prefixes, KEEP.OUT.ATTRS = FALSE, stringsAsFactors = FALSE)
  combos <- combos[rev(seq_along(combos))]
  conda_locations <- unlist(.mapply(paste0, combos, NULL))

  # find the potential conda binary path in each case
  conda_locations <- if (is_windows()) {
    paste0(conda_locations, "/condabin/conda.bat")
  } else {
    paste0(conda_locations, "/bin/conda")
  }

  # look for caskroom version (why does it live in a 'base' subdir?)
  caskroom_conda <- "/opt/homebrew/Caskroom/miniforge/base/bin/conda"
  if (file.exists(caskroom_conda))
    conda_locations <- c(conda_locations, caskroom_conda)

  # ensure we expand tilde prefixes
  conda_locations <- path.expand(conda_locations)

  # on Windows, check the registry for a compatible version of Anaconda
  if (is_windows()) {
    anaconda_versions <- windows_registry_anaconda_versions()
    anaconda_versions <- subset(anaconda_versions, anaconda_versions$arch == .Platform$r_arch)
    if (nrow(anaconda_versions) > 0) {

      conda_scripts <- utils::shortPathName(
        file.path(anaconda_versions$install_path, "Scripts", "conda.exe")
      )
      conda_bats <- utils::shortPathName(
        file.path(anaconda_versions$install_path, "condabin", "conda.bat")
      )

      # prefer versions found in the registry to those found in default locations
      conda_locations <- c(conda_bats, conda_scripts, conda_locations)

    }
  }

  # keep only conda locations that exist
  conda_locations <- conda_locations[file.exists(conda_locations)]
  if (length(conda_locations))
    return(conda_locations)

  # explicitly return NULL when no conda found
  NULL

}

condaenv_resolve <- function(envname = NULL) {

  python_environment_resolve(
    envname = envname,
    resolve = identity
  )

}

condaenv_path <- function(envname = NULL) {

  python_environment_resolve(
    envname = envname,
    resolve = function(name) {
      python <- conda_python(name)
      info <- python_info(python)
      info$root
    }
  )

}

#' @export
#' @rdname conda-tools
condaenv_exists <- function(envname = NULL, conda = "auto") {

  # check that conda is installed
  condabin <- tryCatch(conda_binary(conda = conda), error = identity)
  if (inherits(condabin, "error"))
    return(FALSE)

  # check that the environment exists
  python <- tryCatch(conda_python(envname, conda = conda), error = identity)
  if (inherits(python, "error"))
    return(FALSE)

  # validate the Python binary exists
  file.exists(python)

}

conda_args <- function(action, envname = NULL, ...) {

  envname <- condaenv_resolve(envname)

  # use '--prefix' as opposed to '--name' if envname looks like a path
  args <- c(action, "--yes")
  if (grepl("[/\\]", envname))
    args <- c(args, "--prefix", envname, ...)
  else
    args <- c(args, "--name", envname, ...)

  args

}

is_condaenv <- function(dir) {
  file.exists(file.path(dir, "conda-meta"))
}

conda_list_packages <- function(envname = NULL, conda = "auto", no_pip = TRUE) {

  conda <- conda_binary(conda)
  local_conda_paths(conda)
  envname <- condaenv_resolve(envname)

  # create the environment
  args <- c("list")
  if (grepl("[/\\]", envname)) {
    args <- c(args, "--prefix", envname)
  } else {
    args <- c(args, "--name", envname)
  }

  if (no_pip)
    args <- c(args, "--no-pip")

  args <- c(args, "--json")

  output <- system2(conda, shQuote(args), stdout = TRUE)
  status <- attr(output, "status") %||% 0L
  if (status != 0L) {
    fmt <- "error listing conda environment [status code %i]"
    stopf(fmt, status)
  }

  parsed <- jsonlite::fromJSON(output)

  data.frame(
    package     = parsed$name,
    version     = parsed$version,
    requirement = paste(parsed$name, parsed$version, sep = "="),
    channel     = parsed$channel,
    stringsAsFactors = FALSE
  )

}

conda_installed <- function() {
  condabin <- tryCatch(conda_binary(), error = identity)
  if (inherits(condabin, "error"))
    return(FALSE)
  else
    return(TRUE)
}


conda_run <- function(cmd, args = c(), conda = "auto", envname = NULL,
                      run_args = c("--no-capture-output"), ...) {
  # `conda run` is very unreliable, best avoided. known issues:
  #  - fails if user doesn't have write permissions to conda installation
  #  - fails if arguments need to be quoted

  conda <- conda_binary(conda)
  local_conda_paths(conda)
  envname <- condaenv_resolve(envname)

  if (numeric_conda_version(conda) < "4.9")
    stopf(
"`conda_run()` requires conda version >= 4.9.
Run `miniconda_update('%s')` to update conda.", conda)


  if (grepl("[/\\]", envname))
    in_env <- c("--prefix", shQuote(normalizePath(envname)))
  else
    in_env <- c("--name", envname)

  system2t(conda, c("run", in_env, run_args,
                   shQuote(cmd), args), ...)
}

#' Run a command in a conda environment
#'
#' This function runs a command in a chosen conda environment.
#'
#' Note that, whilst the syntax is similar to [`system2()`], the function
#' dynamically generates a shell script with commands to activate the chosen
#' conda environent. This avoids issues with quoting, as discussed in this
#' [GitHub issue](https://github.com/conda/conda/issues/10972).
#'
#' @param cmd The system command to be invoked, as a character string.
#' @param args A character vector of arguments to the command. The arguments should
#'   be quoted e.g. by `shQuote()` in case they contain space or other special
#'   characters (a double quote or backslash on Windows, shell-specific special
#'   characters on Unix).
#' @param cmd_line The command line to be executed, as a character string. This
#'   is automatically generated from `cmd` and `args`, but can be provided
#'   directly if needed (if provided, it overrides `cmd` and `args`).
#' @param conda The path to a `conda` executable. Use `"auto"` to allow
#'   `reticulate` to automatically find an appropriate `conda` binary.
#'   See **Finding Conda** and [conda_binary()] for more details.
#' @param envname The name of, or path to, a conda environment.
#' @param intern A logical (not `NA`) which indicates whether to capture the
#'   output of the command as an R character vector. If `FALSE` (the default), the
#'   return value is the error code (`0` for success).
#' @param echo A logical (not `NA`) which indicates whether to echo the command to
#'   the console before running it.
#'
#'
#' @returns
#' `conda_run2()` runs a command in the desired conda environment. If
#' `intern = TRUE` the output is returned as a character vector; if `intern = FALSE` (the
#' deafult), then the return value is the error code (0 for success). See
#' [shell()] (on windows) or [`system2()`] on macOS or Linux for more details.
#'
#' @export
#' @seealso [`conda-tools`]
# executes a cmd with a conda env active, implemented directly to avoid using `conda run`
# https://github.com/conda/conda/issues/10972
conda_run2 <- function(cmd, args = c(), conda = "auto", envname = NULL,
                       cmd_line = paste(shQuote(cmd), paste(args, collapse = " ")),
                       intern = FALSE, echo = !intern) {
  run <- if (is_windows()) conda_run2_windows else conda_run2_nix
  run(
    conda = conda,
    envname = envname,
    cmd_line = cmd_line,
    intern = intern,
    echo = echo
  )

}

conda_run2_windows <-
  function(cmd, args = c(), conda = "auto", envname = NULL,
           cmd_line = paste(shQuote(cmd), paste(args, collapse = " ")),
           intern = FALSE, echo = !intern) {
  conda <- normalizePath(conda_binary(conda))
  local_conda_paths(conda)

  if (identical(envname, "base"))
    envname <- file.path(dirname(conda), "../..")
  else
    envname <- condaenv_resolve(envname)

  if (grepl("[/\\]", envname))
    envname <- normalizePath(envname)

  activate.bat <- normalizePath(file.path(dirname(conda), "activate.bat"),
                                mustWork = FALSE)

  activate_cmd <-
    if (file.exists(activate.bat)) {
      paste("CALL", shQuote(activate.bat), shQuote(envname))
    } else {
      paste("CALL", shQuote(conda), "activate", shQuote(envname))
    }

  fi <- tempfile(fileext = ".bat")
  on.exit(unlink(fi))
  writeLines(c(
    if (!echo) "@echo off",
    activate_cmd,
    cmd_line
  ), fi)

  shell(fi, intern = intern)
}

conda_run2_nix <-
  function(cmd, args = c(), conda = "auto", envname = NULL,
           cmd_line = paste(shQuote(cmd), paste(args, collapse = " ")),
           intern = FALSE, echo = !intern) {
  conda <- normalizePath(conda_binary(conda))
  local_conda_paths(conda)

  if (!identical(envname, "base")) {
    envname <- condaenv_resolve(envname)
    if (grepl("[/\\]", envname))
      envname <- normalizePath(envname)
  }

  fi <- tempfile(fileext = ".sh")
  on.exit(unlink(fi))

  stdout <- if (identical(intern, FALSE)) "" else intern

  if (startsWith(basename(conda), "micromamba")) {

    envflag <- if(grepl("[/\\]", envname)) "-p" else "-n"
    if(echo)
      system2 <- system2t
    result <- system2(conda, c('run', envflag, envname, cmd_line),
                      stdout = stdout)

    error_status <- attr(result, "status")
    if (!is.null(error_status))
      stop("Error ", error_status, " occurred while running conda command")

    return(result)

  }


  activate <- normalizePath(file.path(dirname(conda), "activate"))
  commands <- c(
    paste(".", activate),
    if (!identical(envname, "base"))
      paste("conda activate", shQuote(envname)),
    cmd_line
  )

  # set -x is too verbose, includes all the commands made by conda scripts
  # so we manually echo the top-level commands only
  if (echo)
    commands <- as.vector(rbind(
      paste("echo", shQuote(paste("+", commands))),
      commands))

  writeLines(commands, fi)
  system2(Sys.which("bash"), fi, stdout = stdout)

}


conda_info <- function(conda = "auto") {
  conda <- normalizePath(conda_binary(conda))
  json <- system2(conda, c("info", "--json"), stdout = TRUE)
  jsonlite::parse_json(json, simplifyVector = TRUE)
}

is_conda_python <- function(python) {
  root <- if (is_windows())
    dirname(python)
  else
    dirname(dirname(python))

  file.exists(file.path(root, "conda-meta"))
}


get_python_conda_info <- function(python) {

  stopifnot(is_conda_python(python))

  root <- if (is_windows())
    dirname(python)
  else
    dirname(dirname(python))

  if (dir.exists(file.path(root, "condabin"))) {
    # base conda env
    conda <- if (is_windows())
      file.path(root, "condabin/conda.bat")
    else
      file.path(root, "bin/conda")
  } else {
    # not base env
    # in ArcGIS env, conda.exe lives in a parent directory
    exe <- file.path(root, "../..", "Scripts", "conda.exe")
    exe <- normalizePath(exe, winslash = "/", mustWork = FALSE)
    if (is_windows() && file.exists(exe)) {
      conda <- exe
    } else {
      # parse conda-meta history to find the conda binary that created it
      conda <- conda_history_find(root)
    }
  }

  if (is.null(conda)) {
    conda <- NA
  } else {
    conda <- normalizePath(conda, winslash = "/", mustWork = FALSE)
    if(!file.exists(conda))
      conda <- NA
  }

  list(
    conda = conda,
    root = normalizePath(root, winslash = "/", mustWork = TRUE)
  )

}


conda_history_find <- function(path) {
  exe <- if (is_windows()) "conda.exe" else "conda"

  # read history file
  histpath <- file.path(path, "conda-meta/history")
  if (!file.exists(histpath))
    return(NULL)

  history <- readLines(histpath, warn = FALSE)

  # look for cmd line
  pattern <- "^[[:space:]]*#[[:space:]]*cmd:[[:space:]]*"
  lines <- grep(pattern, history, value = TRUE)
  if (length(lines) == 0)
    return(NULL)

  # get path to conda script used
  script <- sub(
    "^#\\s+cmd: (.+?)\\s+(env\\s+create|create|rename)\\s+.*",
    "\\1", lines[[1]], perl = TRUE
  )
  # on Windows, a wrapper script is recorded in the history,
  # so instead attempt to find the real conda binary
  if(is_windows())
    conda <- file.path(dirname(script), exe)
  else
    conda <- script
  normalizePath(conda, winslash = "/", mustWork = FALSE)

}

conda_prefix <- function(conda = "auto") {
  conda <- normalizePath(conda_binary(conda),
                         winslash = "/", mustWork = TRUE)
  if(!is_windows())
    # PREFIX/bin/conda
    return(dirname(dirname(conda)))

  # on Windows, conda can be a few places:
  ## PREFIX/Scripts/conda.exe
  ## PREFIX/condabin/conda.bat
  ## PREFIX/conda.exe
  ## others? maybe under mingw-32/ or Library/ or Tools/?
  ## we punt and just ask conda
  system2(conda, c("info", "--base"), stdout = TRUE)
}

conda_bin_paths <- function(conda = "auto") {
  prefix <- conda_prefix(conda)
  paths <- file.path(prefix, c(
    "condabin",
    "bin",
    "Scripts",
    "Library/bin",
    "Library/usr/bin",
    "Library/mingw-w64/bin"
  ))
  paths[dir.exists(paths)]
}


local_conda_paths <- function(conda, action = "prefix",
                              .local_envir = parent.frame()) {
  withr::local_path(conda_bin_paths(conda), action, .local_envir)
}
