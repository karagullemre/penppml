#' Checking for Perfect Multicollinearity
#'
#' \code{collinearity_check} checks for perfect multicollinearity in a model with high-dimensional
#' fixed effects. It calls \code{lfe::demeanlist} in order to partial out the fixed effects, and then
#' uses \code{stats::lm.wfit} to discard linearly dependent variables.
#'
#' @param y Dependent variable (a numeric vector).
#' @param x Regressor matrix.
#' @param fes List of fixed effects.
#' @param hdfetol Tolerance for the centering, passed on to \code{lfe::demeanlist}.
#'
#' @return A numeric vector containing the variables that pass the collinearity check.

collinearity_check <- function(y, x=NULL, fes=NULL, hdfetol, colcheck_x_fes=FALSE, colcheck_x=FALSE) {
  # Actually collinearity check does not make sense without x
  if(missing(x)){
    stop("Please provide x.")
  }
  mu  <- (y + mean(y)) / 2
  z   <- (y - mu) / mu + log(mu)
  z[which(z==Inf)] <- 0 # test
  reg_z  <- matrix(z)
  if(!missing(x)){
  reg_x  <- x
  }
  mu  <- (y + mean(y)) / 2

  if(!missing(fes)){
    if(is.null(fes)){
      z_resid <- collapse::fwithin(x=reg_z, g=factor(rep(1,length(reg_z))), w = mu)
      if(!missing(x)){
        x_resid <- collapse::fwithin(x=reg_x,g=factor(rep(1,length(reg_z))), w = mu)
      }
    }else{
      z_resid <-  collapse::fhdwithin(reg_z, fes, w = mu)
      if(!missing(x)){
        x_resid <- collapse::fhdwithin(reg_x, fes, w = mu)
      }
    }
  } else {
    z_resid <- reg_z
    if(!missing(x)){
      x_resid <- reg_x
    }
  }

  if(!missing(x)){

    #Exclude x which have zero variance
    x_var <- var(x)
    include_x_var <- which(diag(x_var)!=0)
    if (length(which(diag(x_var)==0)) != 0){
      message(paste("The following variables are dropped because their variation is equal zero:", paste(names(which(diag(x_var)==0)), collapse=" ")))
    }

    if(colcheck_x_fes==TRUE){
      orig_sds <- matrixStats::colSds(x)
      res_sds <- matrixStats::colSds(x_resid)
      frac_sds <- res_sds/orig_sds
      include_x_first <- union(which(!is.na(frac_sds)), which(frac_sds >= 1e-5))
      rm(res_sds, orig_sds)
      if(!is.null(names(which(frac_sds < 1e-5)))){
      message(
      paste("The following variables have been dropped, because most of their variation is explained by the fixed effects: ", paste(names(which(frac_sds < 1e-2)), collapse=" ")))
      }
    }

  if(colcheck_x==TRUE){
    check <- stats::lm.wfit(x_resid, z_resid, mu)
    if(length(names(which(is.na(check$coefficients)))) != 0){
    message(paste("The following variables have been dropped, due to collinearity: ", paste(names(which(is.na(check$coefficients))), collapse=" ")))
    }
  }
  }

  if(colcheck_x_fes==TRUE & colcheck_x==TRUE ){
    include_x <- union(union(include_x_first, which(!is.na(check$coefficients))), include_x_var)
  } else  if (colcheck_x_fes==FALSE & colcheck_x == TRUE ){
      include_x <- union(which(!is.na(check$coefficients)), include_x_var)
  } else if(colcheck_x_fes==TRUE & colcheck_x == FALSE){
        include_x <- union(include_x_first, include_x_var)
  }
 }


#' Cluster-robust Standard Error Estimation
#'
#' \code{cluster_matrix} is a helper for computation of cluster-robust standard errors.
#'
#' @param e Vector of residuals.
#' @param cluster Vector of clusters.
#' @param x Regressor matrix.
#'
#' @return Gives the XeeX matrix.
#' @importFrom rlang .data

cluster_matrix <- function(e, cluster, x) {
  K <- ncol(x)
  vars      <- data.frame(e = e, cluster = factor(cluster, exclude = TRUE), x = x)
  vars      <- vars[order(vars$cluster), ] #5780 is missing...
  vars$indx <- with(vars, ave(seq_along(cluster), cluster, FUN = seq_along))

  sizes <- collapse(vars$indx, by = list(vars$cluster), FUN = max)

  if(is.null(K)){
    X <- data.matrix(vars[, 3])
  } else{
    X <- data.matrix(vars[, 3:(2 + K)])
  }

  e <- as.matrix(vars[, 1])
  rm(vars)
  XeeX <- xeex(X, e, sizes)        #XeeX matrix for cluster-robust SEs
  return(XeeX)
}


collapse = function(x, by, FUN, keep.by = FALSE) {
  if (keep.by == TRUE) {
    data.matrix(stats::aggregate(x = x, by = by, FUN = FUN))
  }
  else {
    data.matrix(stats::aggregate(x = x, by = by, FUN = FUN)[, -1:-length(by)])
  }
}


#' Weighted Standardization
#'
#' Performs weighted standardization of x variables. Used in \code{fastridge}.
#'
#' @param x Regressor matrix.
#' @param weights Weights.
#' @param intercept Logical. If \code{TRUE}, adds an intercept.
#' @param return.sd Logical. If \code{TRUE}, it returns standard errors for the means.
#'
#' @return If \code{return.sd == FALSE}, it gives the matrix of standardized regressors. If
#' \code{return.sd == TRUE}, then it returns the vector of standard errors of the means of the
#' variables.


standardize_wt <- function(x, weights = rep(1/n, n), intercept = TRUE, return.sd = FALSE) {
  n     <- nrow(x)
  nvars <- ncol(x)
  if (intercept) {
    xm <- fastwmean(x, weights)
  } else {
    xm <- rep(0.0, times = nvars)
  }
  xs <- faststddev(x, weights)

  if (return.sd == TRUE) {
    return(xs)
  }
  else {
    if (!inherits(x, "sparseMatrix")) x_std <- t((t(x) - xm) / xs)
    return(x_std)
  }
}


#' Finding Ridge Regression Solutions
#'
#' A wrapper around \code{fastridgeCpp}, for faster computation of the analytical solution for
#' ridge regression.
#'
#' @param x Regressor matrix.
#' @param y Dependent variable (a numeric vector).
#' @param weights Vector of weights.
#' @param lambda Penalty parameter.
#' @param standardize Logical. If \code{TRUE}, x is standardized using the \code{weights}.
#'
#' @return A vector of coefficient (beta) estimates.


fastridge <- function(x, y, weights = rep(1/n, n), lambda, standardize = TRUE) {
  n <- length(y)
  if (standardize) {
    b <- fastridgeCpp(sqrt(weights) * standardize_wt(x, weights), sqrt(weights) * y, lambda)
    beta <- b / faststddev(x, weights)
  } else {
    beta <- fastridgeCpp(sqrt(weights) * x, sqrt(weights) * y, lambda)
  }
  result <- list("beta" = beta)
  return(result)
}


#' Generating a List of Fixed Effects
#'
#' \code{genfes} generates a list of fixed effects by creating interactions of paired factors.
#'
#' @param data A data frame including the factors.
#' @param inter A list: each element includes the variables to be interacted (both names and column
#    and column numbers are supported).
#'
#' @return A list containing the desired interactions of \code{vars}, with the same length as \code{inter}.

genfes <- function(data, inter) {
  fes <- list()

  for (i in seq_along(inter)) {
    fes[[paste(names(data[, inter[[i]]]), collapse = "_")]] <- interaction(data[, inter[[i]]])
  }
  return(fes)
}

#' Generating Model Structure
#'
#' \code{genmodel} transforms a data frame into the needed components for our main functions (a y vector,
#' a x matrix and a fes list).
#'
#' @param data A data frame containing all relevant variables.
#' @param dep A string with the name of the independent variable or a column number.
#' @param indep A vector with the names or column numbers of the regressors. If left unspecified,
#'    all remaining variables (excluding fixed effects) are included in the regressor matrix.
#' @param fixed A vector with the names or column numbers of factor variables identifying the fixed effects,
#'    or a list with the desired interactions between variables in \code{data}.
#' @param cluster Optional. A string with the name of the clustering variable or a column number.
#'     It's also possible to input a vector with several variables, in which case the interaction of
#'     all of them is taken as the clustering variable.
#' @param selectobs Optional. A vector indicating which observations to use.
#'
#' @return A list with four elements:
#' \itemize{
#'   \item \code{y}: y vector.
#'   \item \code{x}: x matrix.
#'   \item \code{fes}: list of fixed effects.
#'   \item \code{cluster}: cluster vector.
#' }

genmodel <- function(data, dep = NULL, indep = NULL, fixed = NULL, cluster = NULL, selectobs = NULL) {
  # First, we filter using selectobs:
  if (!is.null(selectobs)) data <- data[selectobs, ]

  # Then we deal with y:
  if (is.numeric(dep) | is.character(dep)) {
    y <- data[, dep]
  } else {
    stop("Unsupported format for dependent variable: dep must be a character or numeric vector.")
  }

  # Now the fes:
  if (is.numeric(fixed) | is.character(fixed)) {
    fes <- as.list(data[, fixed])
  } else if (is.list(fixed)) {
    fes <- genfes(data = data, inter = fixed)
  } else if (is.null(fixed)) {
    fes <- NULL
  } else {
    stop("Unsupported format for fixed effects: fixed must be a numeric or character vector or a list
         of numeric or character vectors.")
  }

  # Next the clusters (if any):
  if (is.numeric(cluster) | is.character(cluster)) {
    cluster <- interaction(data[, cluster])
  } else if (!is.null(cluster)) {
    stop("Unsupported format for clusters: cluster must be a variable name or column number.")
  }

  # Finally, the x:
  if (is.numeric(indep) | is.character(indep)) {
    x <- data.matrix(data[, indep])
  } else if (is.null(indep)) {
    fixed <- unique(unlist(fixed)) # We get rid of the list structure.
    if (is.character(dep)) dep <- which(names(data) %in% dep)  # This line and the following ensure that the default
    if (is.character(fixed)) fixed <- which(names(data) %in% fixed)  # selection works when dep and fes are names (not column numbers).
    x <- data.matrix(data[, -c(dep, fixed)])
    cat("User did not specify independent variables. By default, the function takes all variables
        not included in 'dep' or 'fixed' as regressors.")
  } else {
    stop("Unsupported format for independent variables: x must be a character or numeric vector.")
  }
  if (is.null(cluster)) {
    return(list(y = y, x = x, fes = fes))
  } else {
    return(list(y = y, x = x, fes = fes, cluster = cluster))
  }
}

