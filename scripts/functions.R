dna_to_cellid <- function(x){
    sub("([A-Z]{3}[0-9]{5})(D?)_([A-Z][0-9]{2}).*","\\1.\\3", x)
}
rna_to_cellid <- function(x){
    sub("([A-Z]{3}[0-9]{5})(R?).([A-Z][0-9]{2}).*","\\1.\\3", x)
}
# Cell to plate id
cellid_to_plateid <- function(x){
    sub("([A-Z]{3}[0-9]{5}).*","\\1", x)
}
cellid_to_well <- function(x){
    sub("([A-Z]{3}[0-9]{5}).([A-Z][0-9]{2})","\\2", x)
}
cellid_to_bamfile <- function(x, path="/proj/sens2018557/dntr/aligned"){
    r <- sub("([A-Z]{3}[0-9]{5})\\.([A-Z][0-9]{2})","\\1D_\\2.dedup.bam", x)
    if(!is.null(path)) r <- paste(path, r, sep="/")
    return(r)
}
cellid_to_bedfile <- function(x, path="/proj/sens2018557/dntr/aligned"){
    r <- sub("([A-Z]{3}[0-9]{5})\\.([A-Z][0-9]{2})","\\1D_\\2.bed.gz", x)
    if(!is.null(path)) r <- paste(path, r, sep="/")
    return(r)
}
cellid_to_row <- function(x){
    sub("([A-Z]{3}[0-9]{5}).([A-Z])[0-9]{2}","\\2", x)
}
cellid_to_col <- function(x){
    sub("([A-Z]{3}[0-9]{5}).[A-Z]([0-9]{2})","\\2", x)
}

norm.log.counts <- function(counts) {
    norm.fact <- colSums(counts)
    counts.norm <- t( apply(counts, 1, function(x) {x/norm.fact*1000000+1}))
    counts.log <- log2(counts.norm)
    rownames(counts.log) <- rownames(counts)
    counts.log
}

get.cutoff.lognorm <- function(my.counts.log, quantile.cut=0.001, gene.name='ACTB') {
    cl.act <- my.counts.log[gene.name,]
    cl.act.m <- median(cl.act)
    cl.act.sd <- sqrt(sum((cl.act[cl.act > cl.act.m] - cl.act.m)^2)/(sum(cl.act  > cl.act.m)-1))
    my.cut <- qnorm(p=quantile.cut, mean=cl.act.m, sd=cl.act.sd)
    my.cut
}

load_seurat_rna <- function(counts.file=NULL, mincount=2e4, minquant=0.01, genequant="ACTB", meanexpr_cutoff=0.3, disp_cutoff=0.5, assay="RNA", plot=F, verbose=F){
    if(is.character(counts.file)){
        cat(paste("^\tLoad counts from", counts.file, "\n"))
        if(verbose) counts <- data.table::fread(counts.file, sep="\t", stringsAsFactors=F, header=T, data.table=F)
        rownames(counts) <- counts[[1]]
        counts[[1]] <- NULL
    } else {
        if(verbose) cat("\t^Load counts from table\n")
        if(!is.matrix(counts.file) & !is.data.frame(counts.file)) stop("Could not recognize counts table format")
        counts <- counts.file
    }
    if(verbose) cat("\t^Listing plates\n")
    if(verbose) cellid_to_plateid(colnames(counts)) %>% table
    if(verbose) cat("\t^Filter and log2 transform counts\n")
    if(verbose) cat("\tMinimum count/cell:",mincount,"\n")
    if(verbose) cat("\tQuantile cutoff: ",minquant," (",genequant,")\n",sep="")
    ercc <- grepl("^ERCC\\-[0-9]*$", rownames(counts))
    nongenes <- grepl("^__", rownames(counts)) # HTseq stat additions
    filtered.counts <- counts[!ercc & !nongenes,] %>% 
        subset(rowSums(.)>0) %>% # Drop genes (rows) with 0 counts in all samples
        subset(select=colSums(.)>mincount) %>% # Drop cells (cols) with total read count < minimum count
        as.matrix()
    n_countsfilt <- ncol(counts)-ncol(filtered.counts)
    countsfilter <- setdiff(colnames(counts), colnames(filtered.counts))
    counts.log1 <- norm.log.counts(filtered.counts) # Log2 of counts per million mapped reads (log2 CPM)
    # Apply 2nd filter, low ACTB expression
    actb_cutoff <- get.cutoff.lognorm(counts.log1, quantile.cut=minquant, gene.name=genequant)
    good.cells <- counts.log1[genequant,] > actb_cutoff
    filtered.counts <- filtered.counts[,good.cells]
    if(verbose) cat("\t^Dropped ",n_countsfilt," (low counts) + ",sum(!good.cells)," (low ACTB) of ", ncol(counts)," cells (",round((n_countsfilt+sum(!good.cells))/ncol(counts)*100,1),"%)\n",sep="")
    # Plots
    if(plot){
        colsumhist <- colSums(counts[!ercc & !nongenes, ]) %>% enframe("cell_id","colsum") %>% 
            mutate(plate_id=cellid_to_plateid(cell_id))
        phist1 <- colsumhist %>% ggplot(aes(log10(colsum))) + ggridges::geom_density_ridges(aes(y=plate_id)) + 
            geom_vline(xintercept=log10(mincount), color="red")
        actbhist <- counts.log1[genequant,] %>% enframe("cell_id","ACTB") %>% 
            mutate(plate_id=cellid_to_plateid(cell_id))
        phist2 <- actbhist %>% ggplot(aes(ACTB)) + ggridges::geom_density_ridges(aes(y=plate_id)) + 
            geom_vline(xintercept=actb_cutoff, color="red")
        pqc <- cowplot::plot_grid(phist1,phist2,ncol=2)
    } else {pqc=NA}
    # Take filtered counts and create Seurat object
    if(verbose) cat("\t^Listing plates, after filtering\n")
    if(verbose) cellid_to_plateid(colnames(filtered.counts)) %>% table
    dat <- CreateSeuratObject(filtered.counts, names.field=1, names.delim="\\.", assay = assay)
    return(list(counts=filtered.counts, seurat=dat, qcplot=pqc, countfilter=countsfilter, genefilter=good.cells))
}

psoptim1 <- function (par, fn, gr = NULL, ..., lower=-1, upper=1,
                      start.state = NULL,
                      Xinit = NULL,
                      control = list()) {
    fn1 <- function(par) fn(par, ...)/p.fnscale
    mrunif <- function(n,m,lower,upper) {
        return(matrix(runif(n*m,0,1),nrow=n,ncol=m)*(upper-lower)+lower)
    }
    norm <- function(x) sqrt(sum(x*x))
    rsphere.unif <- function(n,r) {
        temp <- runif(n)
        return((runif(1,min=0,max=r)/norm(temp))*temp)
    }
    svect <- function(a,b,n,k) {
        temp <- rep(a,n)
        temp[k] <- b
        return(temp)
    }
    mrsphere.unif <- function(n,r) {
        m <- length(r)
        temp <- matrix(runif(n*m),n,m)
        return(temp%*%diag(runif(m,min=0,max=r)/apply(temp,2,norm)))
    }
    npar <- length(par)
    lower <- as.double(rep(lower, ,npar))
    upper <- as.double(rep(upper, ,npar))
    con <- list(trace = 0, fnscale = 1, maxit = 1000L, maxf = Inf,
                abstol = -Inf, reltol = 0, REPORT = 10,
                s = NA, k = 3, p = NA, w = 1/(2*log(2)),
                c.p = .5+log(2), c.g = .5+log(2), d = NA,
                v.max = NA, rand.order = TRUE, max.restart=Inf,
                maxit.stagnate = Inf, eps.stagnate = 1e-3,
                vectorize=FALSE, hybrid = FALSE, hybrid.control = NULL,
                trace.stats = FALSE, type = "SPSO2007", return.swarm = FALSE)
    nmsC <- names(con)
    con[(namc <- names(control))] <- control
    if (length(noNms <- namc[!namc %in% nmsC])) 
        warning("unknown names in control: ", paste(noNms, collapse = ", "))
    ## Argument error checks
    if (any(upper==Inf | lower==-Inf))
        stop("fixed bounds must be provided")
    
    p.type <- pmatch(con[["type"]],c("SPSO2007","SPSO2011"))-1
    if (is.na(p.type)) stop("type should be one of \"SPSO2007\", \"SPSO2011\"")
    
    p.trace <- con[["trace"]]>0L # provide output on progress?
    p.fnscale <- con[["fnscale"]] # scale funcion by 1/fnscale
    p.maxit <- con[["maxit"]] # maximal number of iterations
    p.maxf <- con[["maxf"]] # maximal number of function evaluations
    p.abstol <- con[["abstol"]] # absolute tolerance for convergence
    p.reltol <- con[["reltol"]] # relative minimal tolerance for restarting
    p.report <- as.integer(con[["REPORT"]]) # output every REPORT iterations
    p.s <- ifelse(is.na(con[["s"]]),ifelse(p.type==0,floor(10+2*sqrt(npar)),40),
                  con[["s"]]) # swarm size
    p.p <- ifelse(is.na(con[["p"]]),1-(1-1/p.s)^con[["k"]],con[["p"]]) # average % of informants
    p.w0 <- con[["w"]] # exploitation constant
    if (length(p.w0)>1) {
        p.w1 <- p.w0[2]
        p.w0 <- p.w0[1]
    } else {
        p.w1 <- p.w0
    }
    p.c.p <- con[["c.p"]] # local exploration constant
    p.c.g <- con[["c.g"]] # global exploration constant
    p.d <- ifelse(is.na(con[["d"]]),norm(upper-lower),con[["d"]]) # domain diameter
    p.vmax <- con[["v.max"]]*p.d # maximal velocity
    p.randorder <- as.logical(con[["rand.order"]]) # process particles in random order?
    p.maxrestart <- con[["max.restart"]] # maximal number of restarts
    p.maxstagnate <- con[["maxit.stagnate"]] # maximal number of iterations without improvement
    p.epsstagnate <- con[["eps.stagnate"]] # Used for max.stagnate
    p.vectorize <- as.logical(con[["vectorize"]]) # vectorize?
    if (is.character(con[["hybrid"]])) {
        p.hybrid <- pmatch(con[["hybrid"]],c("off","on","improved"))-1
        if (is.na(p.hybrid)) stop("hybrid should be one of \"off\", \"on\", \"improved\"")
    } else {
        p.hybrid <- as.integer(as.logical(con[["hybrid"]])) # use local BFGS search
    }
    p.hcontrol <- con[["hybrid.control"]] # control parameters for hybrid optim
    if ("fnscale" %in% names(p.hcontrol))
        p.hcontrol["fnscale"] <- p.hcontrol["fnscale"]*p.fnscale
    else
        p.hcontrol["fnscale"] <- p.fnscale
    p.trace.stats <- as.logical(con[["trace.stats"]]) # collect detailed stats?
    p.returnswarm <- as.logical(con[["return.swarm"]]) # return final swarm?
    if (p.trace) {
        message("S=",p.s,", K=",con[["k"]],", p=",signif(p.p,4),", w0=",
                signif(p.w0,4),", w1=",
                signif(p.w1,4),", c.p=",signif(p.c.p,4),
                ", c.g=",signif(p.c.g,4))
        message("v.max=",signif(con[["v.max"]],4),
                ", d=",signif(p.d,4),", vectorize=",p.vectorize,
                ", hybrid=",c("off","on","improved")[p.hybrid+1])
        if (p.trace.stats) {
            stats.trace.it <- c()
            stats.trace.error <- c()
            stats.trace.f <- NULL
            stats.trace.x <- NULL
        }
    }
    ## Initialization
    if (p.reltol!=0) p.reltol <- p.reltol*p.d
    if (p.vectorize) {
        lowerM <- matrix(lower,nrow=npar,ncol=p.s)
        upperM <- matrix(upper,nrow=npar,ncol=p.s)
    }
    # Initialize solution matrix, create random if not supplied. MARTIN
    X <- Xinit
    if(is.null(X)) {
        X <- mrunif(npar,p.s,lower,upper)
    }
    # Check validity of user-supplied X
    if(nrow(X) != npar | ncol(X) != p.s)
        stop(paste("User-supplied swarm start state is not conformant with other arguments. nrow=", nrow(X), "npar=", npar, "ncol=", ncol(X), "p.s=", p.s))
    if (!any(is.na(par)) && all(par>=lower) && all(par<=upper)) X[,1] <- par
    # Initialize direction/speed vectors
    if (p.type==0) {
        V <- (mrunif(npar,p.s,lower,upper)-X)/2
    } else { ## p.type==1
        V <- matrix(runif(npar*p.s,min=as.vector(lower-X),max=as.vector(upper-X)),npar,p.s)
        p.c.p2 <- p.c.p/2 # precompute constants
        p.c.p3 <- p.c.p/3
        p.c.g3 <- p.c.g/3
        p.c.pg3 <- p.c.p3+p.c.g3
    }
    if (!is.na(p.vmax)) { # scale to maximal velocity
        temp <- apply(V,2,norm)
        temp <- pmin.int(temp,p.vmax)/temp
        V <- V%*%diag(temp)
    }
    f.x <- apply(X,2,fn1) # first evaluations
    #  f.x[is.na(f.x)] <- 3000 # MARTIN
    stats.feval <- p.s
    P <- X
    f.p <- f.x
    P.improved <- rep(FALSE,p.s)
    i.best <- which.min(f.p)
    error <- f.p[i.best]
    init.links <- TRUE
    if (p.trace && p.report==1) {
        message("It 1: fitness=",signif(error,4))
        if (p.trace.stats) {
            stats.trace.it <- c(stats.trace.it,1)
            stats.trace.error <- c(stats.trace.error,error)
            stats.trace.f <- c(stats.trace.f,list(f.x))
            stats.trace.x <- c(stats.trace.x,list(X))
        }
    }
    ## Iterations
    stats.iter <- 1
    stats.restart <- 0
    stats.stagnate <- 0
    # Check stop condition
    while (stats.iter<p.maxit && stats.feval<p.maxf && error>p.abstol &&
           stats.restart<p.maxrestart && stats.stagnate<p.maxstagnate) {
        stats.iter <- stats.iter+1
        if (p.p!=1 && init.links) {
            links <- matrix(runif(p.s*p.s,0,1)<=p.p,p.s,p.s)
            diag(links) <- TRUE
        }
        ## The swarm moves
        if (!p.vectorize) {
            if (p.randorder) {
                index <- sample(p.s)
            } else {
                index <- 1:p.s
            }
            for (i in index) {
                if (p.p==1)
                    j <- i.best
                else
                    j <- which(links[,i])[which.min(f.p[links[,i]])] # best informant
                temp <- (p.w0+(p.w1-p.w0)*max(stats.iter/p.maxit,stats.feval/p.maxf))
                V[,i] <- temp*V[,i] # exploration tendency
                if (p.type==0) {
                    V[,i] <- V[,i]+runif(npar,0,p.c.p)*(P[,i]-X[,i]) # exploitation
                    if (i!=j) V[,i] <- V[,i]+runif(npar,0,p.c.g)*(P[,j]-X[,i])
                } else { # SPSO 2011
                    if (i!=j)
                        temp <- p.c.p3*P[,i]+p.c.g3*P[,j]-p.c.pg3*X[,i] # Gi-Xi
                    else
                        temp <- p.c.p2*P[,i]-p.c.p2*X[,i] # Gi-Xi for local=best
                    V[,i] <- V[,i]+temp+rsphere.unif(npar,norm(temp))
                }
                if (!is.na(p.vmax)) {
                    temp <- norm(V[,i])
                    if (temp>p.vmax) V[,i] <- (p.vmax/temp)*V[,i]
                }
                X[,i] <- X[,i]+V[,i]
                ## Check bounds
                temp <- X[,i]<lower
                if (any(temp)) {
                    X[temp,i] <- lower[temp]
                    V[temp,i] <- 0
                }
                temp <- X[,i]>upper
                if (any(temp)) {
                    X[temp,i] <- upper[temp]
                    V[temp,i] <- 0
                }
                ## Evaluate function
                if (p.hybrid==1) {
                    temp <- optim(X[,i],fn,gr,...,method="L-BFGS-B",lower=lower,
                                  upper=upper,control=p.hcontrol)
                    V[,i] <- V[,i]+temp$par-X[,i] # disregards any v.max imposed
                    X[,i] <- temp$par
                    f.x[i] <- temp$value
                    stats.feval <- stats.feval+as.integer(temp$counts[1])
                } else {
                    f.x[i] <- fn1(X[,i])
                    #          if(is.na(f.x[i])) {  #MARTIN
                    #              f.x[i] <- 3000   #MARTIN
                    #          }                    #MARTIN
                    stats.feval <- stats.feval+1
                }
                if (f.x[i]<f.p[i]) { # improvement
                    P[,i] <- X[,i]
                    f.p[i] <- f.x[i]
                    if (f.p[i]<f.p[i.best]) {
                        i.best <- i
                        if (p.hybrid==2) {
                            temp <- optim(X[,i],fn,gr,...,method="L-BFGS-B",lower=lower,
                                          upper=upper,control=p.hcontrol)
                            V[,i] <- V[,i]+temp$par-X[,i] # disregards any v.max imposed
                            X[,i] <- temp$par
                            P[,i] <- temp$par
                            f.x[i] <- temp$value
                            f.p[i] <- temp$value
                            stats.feval <- stats.feval+as.integer(temp$counts[1])
                        }
                    }
                }
                if (stats.feval>=p.maxf) break
            }
        } else {
            if (p.p==1)
                j <- rep(i.best,p.s)
            else # best informant
                j <- sapply(1:p.s,function(i)
                    which(links[,i])[which.min(f.p[links[,i]])]) 
            temp <- (p.w0+(p.w1-p.w0)*max(stats.iter/p.maxit,stats.feval/p.maxf))
            V <- temp*V # exploration tendency
            if (p.type==0) {
                V <- V+mrunif(npar,p.s,0,p.c.p)*(P-X) # exploitation
                temp <- j!=(1:p.s)
                V[,temp] <- V[,temp]+mrunif(npar,sum(temp),0,p.c.p)*(P[,j[temp]]-X[,temp])
            } else { # SPSO 2011
                temp <- j==(1:p.s)
                temp <- P%*%diag(svect(p.c.p3,p.c.p2,p.s,temp))+
                    P[,j]%*%diag(svect(p.c.g3,0,p.s,temp))-
                    X%*%diag(svect(p.c.pg3,p.c.p2,p.s,temp)) # G-X
                V <- V+temp+mrsphere.unif(npar,apply(temp,2,norm))
            }
            if (!is.na(p.vmax)) {
                temp <- apply(V,2,norm)
                temp <- pmin.int(temp,p.vmax)/temp
                V <- V%*%diag(temp)
            }
            X <- X+V
            ## Check bounds
            temp <- X<lowerM
            if (any(temp)) {
                X[temp] <- lowerM[temp] 
                V[temp] <- 0
            }
            temp <- X>upperM
            if (any(temp)) {
                X[temp] <- upperM[temp]
                V[temp] <- 0
            }
            ## Evaluate function
            if (p.hybrid==1) { # not really vectorizing
                for (i in 1:p.s) {
                    temp <- optim(X[,i],fn,gr,...,method="L-BFGS-B",lower=lower,
                                  upper=upper,control=p.hcontrol)
                    V[,i] <- V[,i]+temp$par-X[,i] # disregards any v.max imposed
                    X[,i] <- temp$par
                    f.x[i] <- temp$value
                    stats.feval <- stats.feval+as.integer(temp$counts[1])
                }
            } else {
                f.x <- apply(X,2,fn1)
                #        f.x[is.na(f.x)] <- 3000 # MARTIN
                stats.feval <- stats.feval+p.s
            }
            temp <- f.x<f.p
            if (any(temp)) { # improvement
                P[,temp] <- X[,temp]
                f.p[temp] <- f.x[temp]
                i.best <- which.min(f.p)
                if (temp[i.best] && p.hybrid==2) { # overall improvement
                    temp <- optim(X[,i.best],fn,gr,...,method="L-BFGS-B",lower=lower,
                                  upper=upper,control=p.hcontrol)
                    V[,i.best] <- V[,i.best]+temp$par-X[,i.best] # disregards any v.max imposed
                    X[,i.best] <- temp$par
                    P[,i.best] <- temp$par
                    f.x[i.best] <- temp$value
                    f.p[i.best] <- temp$value
                    stats.feval <- stats.feval+as.integer(temp$counts[1])
                }
            }
            if (stats.feval>=p.maxf) break
        }
        if (p.reltol!=0) {
            d <- X-P[,i.best]
            d <- sqrt(max(colSums(d*d)))
            if (d<p.reltol) {
                X <- mrunif(npar,p.s,lower,upper)
                V <- (mrunif(npar,p.s,lower,upper)-X)/2
                if (!is.na(p.vmax)) {
                    temp <- apply(V,2,norm)
                    temp <- pmin.int(temp,p.vmax)/temp
                    V <- V%*%diag(temp)
                }
                stats.restart <- stats.restart+1
                if (p.trace) message("It ",stats.iter,": restarting")
            }
        }
        #    init.links <- f.p[i.best]==error # if no overall improvement
        init.links <- abs(f.p[i.best]-error) < p.epsstagnate # if overall improvement < eps MARTIN
        stats.stagnate <- ifelse(init.links,stats.stagnate+1,0)
        error <- f.p[i.best]
        if (p.trace && stats.iter%%p.report==0) {
            if (p.reltol!=0) 
                message("It ",stats.iter,": fitness=",signif(error,4),
                        ", swarm diam.=",signif(d,4))
            else
                message("It ",stats.iter,": fitness=",signif(error,4))
            if (p.trace.stats) {
                stats.trace.it <- c(stats.trace.it,stats.iter)
                stats.trace.error <- c(stats.trace.error,error)
                stats.trace.f <- c(stats.trace.f,list(f.x))
                stats.trace.x <- c(stats.trace.x,list(X))
            }
        }
        #    cat("stats.iter: ", stats.iter,
        #        ", stats.feval: ", stats.feval,
        #        ", error: ", error,
        #        ", stats.restart: ", stats.restart,
        #        ", stats.stagnate: ", stats.stagnate, "\n")
    }
    
    if (error<=p.abstol) {
        msg <- "Converged"
        msgcode <- 0
    } else if (stats.feval>=p.maxf) {
        msg <- "Maximal number of function evaluations reached"
        msgcode <- 1
    } else if (stats.iter>=p.maxit) {
        msg <- "Maximal number of iterations reached"
        msgcode <- 2
    } else if (stats.restart>=p.maxrestart) {
        msg <- "Maximal number of restarts reached"
        msgcode <- 3
    } else {
        msg <- "Maximal number of iterations without improvement reached"
        msgcode <- 4
    }
    if (p.trace) message(msg)
    o <- list(par=P[,i.best],value=f.p[i.best],
              counts=c("function"=stats.feval,"iteration"=stats.iter,
                       "restarts"=stats.restart),
              convergence=msgcode,message=msg)
    if (p.trace && p.trace.stats) o <- c(o,list(stats=list(it=stats.trace.it,
                                                           error=stats.trace.error,
                                                           f=stats.trace.f,
                                                           x=stats.trace.x)))
    if(p.returnswarm) o <- c(o,list(swarm=X))
    return(o)
}

theme_dntr <- function (font_size = 14, font_family = "Helvetica", line_size = 0.5) {
    half_line <- font_size/2
    small_rel <- 0.857
    small_size <- small_rel * font_size
    theme_grey(base_size = font_size, base_family = font_family) %+replace% 
        theme(panel.background = element_blank(), panel.border = element_rect(fill = NA, colour = "black", size=1), 
              legend.justification = "top", legend.background = element_blank(), legend.key = element_blank(),
              legend.key.size = unit(1, "lines"), strip.background = element_blank(), strip.text=element_text(hjust=0,size=12),
              rect = element_rect(fill = "transparent", color = "black", size = 1, linetype = "solid"), axis.line = element_blank(),
              text = element_text(family = font_family, face = "plain", color = "black", size = font_size, hjust = 0.5, vjust = 0.5, angle = 0, lineheight = 0.9, margin = margin(), debug = FALSE),
              axis.text.x = element_text(color="black", margin = margin(t = small_size/4), vjust = 1), 
              axis.text.y = element_text(color="black", margin = margin(r = small_size/4), hjust = 1), 
              axis.title.x = element_text(margin = margin(t = small_size/4, b = small_size/4)), 
              axis.title.y = element_text(angle = 90, margin = margin(r = small_size/4, l = small_size/4)), 
              axis.ticks = element_line(colour = "black", size = line_size))
}

source_cols <- c("Control"="#9E9E9E", 
                 "ETO 1uM"="#FFEB3B", "ETO 3uM"="#FFC107", "ETO 10uM"="#FF9800", "ETO 30uM"="#FF5722", "ETO 100uM"="#d50000", 
                 "X-ray 1Gy"="#03A9F4", "X-ray 3Gy"="#2196F3", "X-ray 5Gy"="#3F51B5")
