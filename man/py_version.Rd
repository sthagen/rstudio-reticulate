% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/config.R
\name{py_version}
\alias{py_version}
\title{Python version}
\usage{
py_version(patch = FALSE)
}
\arguments{
\item{patch}{boolean, whether to include the patch level in the returned version.}
}
\value{
The version of Python currently used, or \code{NULL} if Python has
not yet been initialized by \code{reticulate}.
}
\description{
Get the version of Python currently being used by \code{reticulate}.
}
