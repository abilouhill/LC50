#' Solar/Satellite Geolocation for Animal Tracking
#'
#' provides facilities for estimating lethal concentrations for a
#' toxin from destructively sampled survival data in the presence of
#' additional stressors and non-ignorable control mortality.
#'
#' @name LC50-package
#' @docType package
#' @author S. Wotherspoon, A. Proctor.
NULL



##' Estimate LC50 from survival data in the presence of additional
##' stressors and non-ignorable control mortality
##'
##' DESCRIBE the model.
##'
##' \code{lc50.fit} is the workhorse function: it is not normally
##' called directly but can be more efficient where the response
##' vector, design matrix and family have already been calculated.
##'
##'
##' @title Estimate LC50 for a toxin
##' @param formula a formula relating log LC50 to covariates
##' describing the aditional stressors.
##' @param concentration the name of variable that is the
##' concentration of the toxin.
##' @param group a factor distinguishing treatment groups for the additional stressors.
##' @param data data frame containing variables in the model.
##' @param start Starting values used to initialize the model.  If
##' \code{start=NULL} these parameters are determined by
##' \code{\link{lc50.initialize}}.
##' @param X a design matrix
##' @param Y a two column matrix of responses
##' @param conc a vector of toxin concentrations
##' @param alpha vector of starting rate parameters
##' @param beta vector of starting coefficients
##' @param gamma vector of control survival parameters
##'
##' @return \code{lc50} returns an object of class inheriting from
##' "lc50". See later in this section.
##'
##' The function \code{\link{summary}} (i.e.,
##' \code{link{summary.lc50}}) can be used to obtain or print a
##' summary of the results and the function \code{\link{anova}} (i.e.,
##' \code{\link{anova.lc50}}) to produce an analysis of deviance table
##' for the tests of additional stressor effects.
##'
##' An LC50 model has several sets of coefficients, the generic
##' accessor function \code{\link{coef}} returns only the beta
##' coeffients.
##'
##' An object of class "lc50" is a list containing at least the
##' following components:
##'
##'
##'
##'
##' \item{\code{logLik}}{the maximized log likelihood.}
##' \item{\code{aic}}{Akaike's information criteria.}
##' \item{\code{alpha}}{a vector of rate coefficients.}
##' \item{\code{gamma}}{a vector of control mortality coefficients.}
##' \item{\code{gamma.cov}}{covariance of the control mortality coefficients.}
##' \item{\code{coefficients}}{a named vector of coefficients.}
##' \item{\code{cov.scaled}}{covariance of the coefficients.}
##' \item{\code{loglc50}}{a named vector of log lc50s for the treatment groups.}
##' \item{\code{loglc50.cov}}{covariance of the lc50s for the treatment groups.}
##' \item{\code{concentration}}{a vector of taxin concentrations.}
##' \item{\code{group}}{a factor distinguishing treatment groups.}
##' \item{\code{x}}{a design matrix relating log lc50 to factors describing the additional stressors.}
##' \item{\code{y}}{a two column matrix of responses, giving the survivals and mortalities.}
##' \item{\code{fitted.values}}{the fitted probability of survival.}
##' \item{\code{deviance}}{the deviance.}
##' \item{\code{df.residual}}{the residual degrees of freedom.}
##' \item{\code{null.deviance}}{the ddeviance of the null model, which fits a single mortality rate to all data.}
##' \item{\code{df.null}}{the degrees of freedom for the null model.}
##' \item{\code{nlm}}{the result of the call to \code{nlm}.}
##' \item{\code{xlevels}}{a record of the levels of the factors used in fitting.}
##' \item{\code{contrasts}}{the contrasts used.}
##' \item{\code{call}}{the matched call.}
##' \item{\code{terms}}{the terms object used.}
##' \item{\code{terms}}{the terms object used.}
##'
##' @export


lc50 <- function(formula,concentration,group,data,start=NULL) {

  ## Record call
  cl <- match.call()

  ## Create the model frame and terms
  mf <- match.call(expand.dots = FALSE)
  m <- match(c("formula", "concentration", "group", "data"), names(mf), 0L)
  mf <- mf[c(1L, m)]
  mf$drop.unused.levels <- TRUE
  mf[[1L]] <- quote(stats::model.frame)
  mf <- eval(mf, parent.frame())
  mt <- attr(mf,"terms")

  ## Extract concentrations
  conc <- mf[,"(concentration)"]

  ## Create the model matrix and response
  X <- model.matrix(mt,mf)
  Y <- model.response(mf)

  ## Determine the treatment groups
  group <- as.factor(mf[,"(group)"])

  ## Fit separate models to each group to generate initial parameter estimates
  if(is.null(start)) start <- lc50.initialize(Y,conc,group)
  alpha <- start$alpha
  gamma <- start$gamma
  beta <- qr.solve(X,start$loglc50[group])
  r <- lc50.fit(X,Y,conc,group,alpha,gamma,beta)
  r <- c(r,
         list(
           xlevels=.getXlevels(mt, mf),
           contrasts=attr(X,"contrasts"),
           call=cl,
           terms=mt,
           model=mf))
  class(r) <- "lc50"
  r
}


##' @rdname lc50
##' @importFrom MASS ginv
lc50.fit <- function(X,Y,conc,group,alpha,gamma,beta) {

  ## Decompose response
  y <- Y[,1]
  N <- rowSums(Y)

  ng <- nlevels(group)

  ## Index of first row of X for each group
  k <- match(levels(group),group)
  Xg <- X[k,,drop=FALSE]

  fitted.pq <- function(alpha,gamma,beta) {
    p <- pnorm(alpha[group]*(log(conc)-X%*%beta))
    q <- pnorm(gamma[group])
    ifelse(conc>0,p*q,q)
  }

  ## Negative log likelihood
  nlogL <- function(pars) {
    alpha <- pars[seq_len(ng)]
    gamma <- pars[ng+seq_len(ng)]
    beta <- pars[-seq_len(2*ng)]
    pq <- fitted.pq(alpha,gamma,beta)
    nll <- -sum(dbinom(y,N,pq,log=TRUE))
    if(!is.finite(nll)) nll <- .Machine$double.xmax
    nll
  }
  ## Minimize negative log likelihood
  mn <- nlm(nlogL,c(alpha,gamma,beta),hessian=TRUE)

  ## Basic parameters
  alpha <- mn$estimate[seq_len(ng)]
  names(alpha) <- levels(group)
  gamma <- mn$estimate[ng+seq_len(ng)]
  names(gamma) <- levels(group)
  beta <- mn$estimate[-seq_len(2*ng)]
  names(beta) <- colnames(X)
  ## Covariance of the beta (is subset of inverse hessian)
  V <- ginv(mn$hessian)[-seq_len(2*ng),-seq_len(2*ng),drop=FALSE]
  colnames(V) <- rownames(V) <- colnames(X)

  ## Compute lc50 and covariance by group
  loglc50 <- as.numeric(Xg%*%beta)
  names(loglc50) <- levels(group)
  loglc50.cov <- Xg%*%V%*%t(Xg)
  colnames(loglc50.cov) <- rownames(loglc50.cov) <- levels(group)

  ## Covariance of the gamma (is subset of inverse hessian)
  gamma.cov <- ginv(mn$hessian)[ng+seq_len(ng),ng+seq_len(ng),drop=FALSE]
  colnames(gamma.cov) <- rownames(gamma.cov) <- levels(group)

  ## Compute the deviance
  fitted <- fitted.pq(alpha,gamma,beta)
  deviance <- -2*sum(dbinom(y,N,fitted,log=T)-dbinom(y,N,y/N,log=T))
  df.residual <- nrow(X)-(ncol(X)+ng)
  null.deviance <- -2*sum(dbinom(y,N,sum(y)/sum(N),log=T)-dbinom(y,N,y/N,log=T))
  df.null <- nrow(X)-(1+ng)
  aic <- 2*(ncol(X)+2*ng+mn$minimum)

  r <- list(logLik=-mn$minimum,
            aic=aic,
            alpha=alpha,
            gamma=gamma,
            gamma.cov=gamma.cov,
            coefficients=beta,
            cov.scaled=V,
            loglc50=loglc50,
            loglc50.cov=loglc50.cov,
            concentration=conc,
            group=group,
            x=X,
            y=Y,
            fitted.values=fitted,
            deviance=deviance,
            df.residual=df.residual,
            null.deviance=null.deviance,
            df.null=df.null,
            nlm=mn)
  class(r) <- "lc50"
  r
}


##' Estimate starting parameters for and LC50 model fit
##'
##' This is the default method for computing the starting values used
##' to initialize an \code{\link{lc50}} model.
##'
##' @title Starting parameters for an LC50 model fit
##' @param Y a two column matrix of the number of survivals and mortalities in each sample.
##' @param conc a vector of tixin concentrations
##' @param group a factor delineating treatment groups
##' @return Return a list of with components
##' \item{\code{alpha}}{the rate parameter for each treatment group}
##' \item{\code{gamma}}{the probit of the control surival for each treatment group}
##' \item{\code{loglc50}}{the log lc50 for each treatment group}
##' @export
lc50.initialize <- function(Y,conc,group) {

  init <- function(Y,conc) {
    X <- cbind(1,ifelse(conc>0,1,0),ifelse(conc>0,log(conc),0))
    glm.fit(X,Y,family=binomial(link=probit))$coefficient
  }

  cfs <- lapply(levels(group),function(g) init(Y[group==g,],conc[group==g]))
  list(alpha=sapply(cfs,function(cs) cs[3]),
       gamma=sapply(cfs,function(cs) cs[1]),
       loglc50=sapply(cfs,function(cs) -sum(cs[1:2])/cs[3]))
}


##' @export
print.lc50 <- function(x,digits = max(3L, getOption("digits") - 3L),...) {
  cat("\nCall:\n", paste(deparse(x$call), sep = "\n", collapse = "\n"), "\n\n", sep = "")
  cat("Coefficients:\n")
  print.default(format(x$coefficients, digits=digits),print.gap=2L,quote=FALSE)
  cat("log LC50:\n")
  print.default(format(x$loglc50, digits=digits),print.gap=2L,quote=FALSE)
  cat("Probit Control Survival:\n")
  print.default(format(x$gamma, digits=digits),print.gap=2L,quote=FALSE)
  invisible(x)
}


##' Summary method for class "\code{lc50}".
##'
##'
##' @title Summmarizing LC50 model fits
##' @param object an object of class \code{lc50}, obtained as the
##' result of a call to \code{\link{lc50}}
##' @param x an object of class \code{summary.lc50}, usually, a result
##' of a call to \code{summary.lc50}.
##' @param digits the number of significant digits to use when printing.
##' @param signif.stars logical. If \code{TRUE}, 'significance stars'
##' are printed for each coefficient.
##' @param ... additional parameters are ignored.
##' @return Returns an object of class \code{summary.lc50}, with components
##' \item{\code{coefficients}}{a table of coefficients.}
##' \item{\code{lc50}}{a table of LC50 for each treatment group.}
##' \item{\code{csurv}}{a table of control survival for each treatment group.}
##' @export
summary.lc50 <- function(object,...) {
  keep <- match(c("call","deviance","aic","contrasts","df.residual","null.deviance","df.null"),names(object),0L)
  cf <- object$coefficients
  cf.se <- sqrt(diag(object$cov.scaled))
  zvalue <- abs(cf)/cf.se
  pvalue <- pvalue <- 2*pnorm(-abs(zvalue))
  coef.table <- cbind(cf, cf.se, zvalue, pvalue)
  dimnames(coef.table) <- list(names(cf), c("Estimate","Std. Error","z value","Pr(>|z|)"))

  loglc50 <- object$loglc50
  loglc50.se <- sqrt(diag(object$loglc50.cov))
  lc50.table <- cbind(loglc50, loglc50.se, exp(loglc50), exp(loglc50-1.96*loglc50.se), exp(loglc50+1.96*loglc50.se))
  dimnames(lc50.table) <- list(names(loglc50), c("Estimate","Std. Error", "LC50", "Lwr 95%", "Upr 95%"))

  gamma <- object$gamma
  gamma.se <- sqrt(diag(object$gamma.cov))
  csurv.table <- cbind(gamma,gamma.se,pnorm(gamma),pnorm(gamma-1.96*gamma.se),pnorm(gamma-1.96*gamma.se))
  dimnames(csurv.table) <- list(names(gamma), c("Estimate","Std. Error", "C Surv", "Lwr 95%", "Upr 95%"))

  r <- c(list(coefficients=coef.table,
              lc50=lc50.table,
              csurv=csurv.table),
         object[keep])
  class(r) <- c("summary.lc50")
  r
}


##' @rdname summary.lc50
##' @export
print.summary.lc50 <- function(x,digits=max(3L,getOption("digits")-3L),
                               signif.stars=getOption("show.signif.stars"),...) {

  cat("\nCall:\n",paste(deparse(x$call),sep="\n",collapse="\n"),"\n\n",sep="")
  cat("\nCoefficients:\n")
  printCoefmat(x$coefficients,digits=digits,signif.stars=signif.stars,na.print="NA",...)
  cat("\n",
      apply(cbind(paste(format(c("Null", "Residual"), justify = "right"), "deviance:"),
                  format(unlist(x[c("null.deviance", "deviance")]), digits = max(5L, digits + 1L)),
                  " on",
                  format(unlist(x[c("df.null", "df.residual")])), " degrees of freedom\n"),
            1L, paste, collapse = " "), sep = "")
  cat("AIC: ", format(x$aic, digits = max(4L, digits + 1L)),"\n")
  cat("\nLC50:\n")
  printCoefmat(x$lc50,digits=digits,cs.ind=1:2,tst.ind=NULL,has.Pvalue=FALSE,na.print="NA",...)
  cat("\nControl Survival:\n")
  printCoefmat(x$csurv,digits=digits,cs.ind=1:2,tst.ind=NULL,has.Pvalue=FALSE,na.print="NA",...)
  cat("\n")
  invisible(x)
}






##' Compute an analysis of deviance table for an LC50 model fit.
##'
##' Specifying a single object gives a sequential analysis of deviance
##' table for that fit. That is, the reductions in the residual
##' deviance as each term of the formula is added in turn are given in
##' as the rows of a table, plus the residual deviances themselves.
##'
##' If more than one object is specified, the table has a row for the
##' residual degrees of freedom and deviance for each model. For all
##' but the first model, the change in degrees of freedom and deviance
##' is also given. (This only makes statistical sense if the models
##' are nested.) It is conventional to list the models from smallest
##' to largest, but this is up to the user.
##'
##' When \code{test} is "LRT" or "Chissq" the table will contain test
##' statistics (and P values) comparing the reduction in deviance for
##' the row to the residuals.
##'
##' @title Analysis of Deviance for lc50 model fits
##' @param object an object of class \code{lc50}, usually obtained as the
##' results from a call to \code{\link{lc50}}
##' @param ... additional objects of class \code{lc50}.
##' @param test a character string, partially matching one of
##' "\code{LRT}", "\code{Chisq}", or "\code{Cp}". See
##' \code{link{stat.anova}}.
##' @return An object of class \code{anova} inheriting from class
##' \code{data.frame}.
##' @export
anova.lc50 <- function(object,...,test = NULL)  {
  ## Handle multiple fits
  dotargs <- list(...)
  named <- if (is.null(names(dotargs))) rep_len(FALSE, length(dotargs)) else (names(dotargs) != "")
  if (any(named))
    warning("the following arguments to 'anova.lc50' are invalid and dropped: ",
            paste(deparse(dotargs[named]), collapse = ", "))
  dotargs <- dotargs[!named]
  is.lc50 <- vapply(dotargs, function(x) inherits(x, "lc50"), NA)
  dotargs <- dotargs[is.lc50]
  if (length(dotargs))
    return(anova.lc50list(c(list(object),dotargs),test = test))

  ## Passed single fit object
  varlist <- attr(object$terms, "variables")
  x <- model.matrix(object)
  varseq <- attr(x, "assign")
  nvars <- max(0, varseq)
  resdev <- resdf <- NULL
  if(nvars > 0) {
    for (i in seq_len(nvars)) {
      beta <- object$coefficients[varseq<i]
      fit <- eval(call("lc50.fit",X=x[,varseq<i,drop=FALSE],
                       Y=object$y,conc=object$concentration,group=object$group,
                       alpha=object$alpha,gamma=object$gamma,beta=beta))
      resdev <- c(resdev, fit$deviance)
      resdf <- c(resdf, fit$df.residual)
    }
  }
  resdf <- c(resdf, object$df.residual)
  resdev <- c(resdev, object$deviance)
  table <- data.frame(c(NA, -diff(resdf)), c(NA, pmax(0, -diff(resdev))), resdf, resdev)
  tl <- attr(object$terms, "term.labels")
  if (length(tl) == 0L) table <- table[1, , drop = FALSE]
  dimnames(table) <- list(c("NULL", tl), c("Df", "Deviance", "Resid. Df", "Resid. Dev"))
  title <- paste0("Analysis of Deviance Table",
                  "\n\nResponse: ", as.character(varlist[-1L])[1L],
                  "\n\nTerms added sequentially (first to last)\n\n")
  df.dispersion <- object$df.residual
  if (!is.null(test))
    table <- stat.anova(table=table,test=test,scale=1,df.scale=df.dispersion,n=NROW(x))
  structure(table, heading = title, class = c("anova", "data.frame"))
}

##' @rdname anova.lc50
##' @export
anova.lc50list <- function (object, ..., test = NULL) {
  responses <- as.character(lapply(object, function(x) deparse(formula(x)[[2L]])))
  sameresp <- responses == responses[1L]
  if (!all(sameresp)) {
    object <- object[sameresp]
    warning(gettextf("models with response %s removed because response differs from model 1",
                     sQuote(deparse(responses[!sameresp]))), domain = NA)
  }
  ns <- sapply(object, function(x) length(x$residuals))
  if (any(ns != ns[1L]))
    stop("models were not all fitted to the same size of dataset")
  nmodels <- length(object)
  if (nmodels == 1)
    return(anova.lc50(object[[1L]], test = test))
  resdf <- as.numeric(lapply(object, function(x) x$df.residual))
  resdev <- as.numeric(lapply(object, function(x) x$deviance))
  table <- data.frame(resdf, resdev, c(NA, -diff(resdf)), c(NA, -diff(resdev)))
  variables <- lapply(object, function(x) paste(deparse(formula(x)), collapse = "\n"))
  dimnames(table) <- list(1L:nmodels, c("Resid. Df", "Resid. Dev", "Df", "Deviance"))
  title <- "Analysis of Deviance Table\n"
  topnote <- paste("Model ", format(1L:nmodels), ": ", variables, sep = "", collapse = "\n")
  if (!is.null(test)) {
    bigmodel <- object[[order(resdf)[1L]]]
    df.dispersion <- min(resdf)
    table <- stat.anova(table=table,test=test,scale=1,
                        df.scale=df.dispersion,n=length(bigmodel$residuals))
  }
  structure(table, heading = c(title, topnote), class = c("anova", "data.frame"))
}




## This is ripped off coef.glm
##' @export
coef.lc50 <- function(object,...) {
  object$coefficients
}

## This is ripped off from vcov.glm
##' @export
vcov.lc50 <- function(object,...) {
  object$cov.scaled
}

## This is ripped off from model.matrix.lm
##' @export
model.matrix.lc50 <- function(object,...) {
  object$x
}


## This is ripped off from model.frame.lm
##' @export
model.frame.lc50 <- function(formula, ...)  {
  dots <- list(...)
  nargs <- dots[match(c("data","concentration","group"),names(dots),0)]
  if (length(nargs) || is.null(formula$model)) {
    fcall <- formula$call
    m <- match(c("formula","data","concentration","group"),names(fcall),0L)
    fcall <- fcall[c(1L, m)]
    fcall$drop.unused.levels <- TRUE
    fcall[[1L]] <- quote(stats::model.frame)
    fcall$xlev <- formula$xlevels
    fcall$formula <- terms(formula)
    fcall[names(nargs)] <- nargs
    env <- environment(formula$terms)
    if (is.null(env))
      env <- parent.frame()
    eval(fcall, env)
  }
  else formula$model
}



## This is ripped off from simulate.lm
##' @importFrom stats simulate
##' @export
simulate.lc50 <- function(object, nsim=1, seed=NULL, ...) {
  if (!exists(".Random.seed", envir = .GlobalEnv, inherits = FALSE))
    runif(1)
  if (is.null(seed))
    RNGstate <- get(".Random.seed", envir = .GlobalEnv)
  else {
    R.seed <- get(".Random.seed", envir = .GlobalEnv)
    set.seed(seed)
    RNGstate <- structure(seed, kind = as.list(RNGkind()))
    on.exit(assign(".Random.seed", R.seed, envir = .GlobalEnv))
  }
  sim <- function(.) {
    y <- rbinom(n,N,ftd)
    y <- cbind(y,N-y)
    colnames(y) <- colnames(object$y)
  }

  ftd <- object$fitted.values
  n <- length(ftd)
  N <- rowSums(object$y)
  val <- vector("list", nsim)
  for (i in seq_len(nsim)) {
    y <- rbinom(n,N,ftd)
    y <- cbind(y,N-y)
    colnames(y) <- colnames(object$y)
    val[[i]] <- y
  }
  class(val) <- "data.frame"
  names(val) <- paste("sim", seq_len(nsim), sep = "_")
  row.names(val) <- rownames(object$y)
  attr(val, "seed") <- RNGstate
  val
}



