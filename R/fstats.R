#' Get FST from genotypes
#'
#' Takes a matrix genotypes as input and calculates FST (Weir and Cockerham 1984)
#' over all populations in the input data. Options to report per SNP
#' or whole region FST value, as well as extended output
#' of individual terms for estimates
#'
#' @param gt genotype matrix, dimensions SNPs x individuals
#' @param popIdx A vector specifying the population label for each individual (column) of the genotype matrix
#' @param region optional flag to return average FST for whole input region
#' @param extended optional flag to return all terms for per-SNP FST
#' @return
#' \itemize{
#'   \item region = TRUE .. average FST over region
#'   \item region = FALSE, extended = FALSE .. a vector of FST per marker
#'   \item region = FALSE, extended = TRUE .. a matrix with numerator and denominator terms of FST (a, b, c in Weir & Cockerham 1984)
#' }
getFstGT <- function(gt, popIdx, region = FALSE, extended = FALSE){

    if(region & extended) stop("'region' & 'extended' flags can't be used together")

    ## set up helper terms
    r <- length(unique(popIdx)) ## number of populations
    gtM <- matrix(as.integer(!is.na(gt)), ncol = ncol(gt)) ## index matrix for non-missing genotypes
    isHet <- matrix(as.integer(gt == 1), ncol = ncol(gt)) ## index matrix for heterozygpote genotypes

    nI <- t(rowsum(t(gtM), popIdx, reorder = FALSE)) ## sample size per SNP and population
    pIBar <- t(rowsum(t(gt), popIdx, reorder = FALSE, na.rm = TRUE)) / nI / 2 ## sample allele frequency per SNP and population
    hIBar <- t(rowsum(t(isHet), popIdx, reorder = FALSE, na.rm = TRUE)) / nI ## proportion of heterozygote individuals per SNP and population

    nBar <- rowSums(nI) / r ## average sample size
    nC <- (r *  nBar - rowSums(nI^2 / (r * nBar))) / (r - 1)

    pBar <- rowSums(nI * pIBar / (r * nBar)) ## average sample allele frequency
    sSqu <- rowSums(nI * (pIBar - pBar)^2 / ((r - 1) * nBar)) ## variance of sample allele frequency
    hBar <- rowSums(nI * hIBar / (r * nBar))  ## average het frequency

    ## final terms for estimator
    a <- nBar/nC * (sSqu - (pBar*(1-pBar) - sSqu*(r-1)/r - hBar/4) / (nBar-1))
    b <- nBar / (nBar - 1) * (pBar * (1 - pBar) - (r - 1) / r * sSqu - (2 * nBar - 1) / (4 * nBar) * hBar)
    c <- hBar / 2

    ## return results
    res <- a / (a + b + c)
    if(region){
        res <- sum(a) / sum(a + b + c)
    }
    if(extended){
        res <- cbind(a, b, c)
    }
    return(res)
}


#' Get FST from allele counts
#'
#' Takes an array of allele counts input and calculates FST over all populations
#' in the input data. This is the moment estimator of Weir and Hill (2002)
#' using sample allele frequncies, assumes no local inbreeding.
#' Options to report per SNP or whole region FST value, as well as
#' extended output of numerator and denominator terms
#'
#' @param p allele counts array, dimensions SNPs x individuals x 2
#' @param region optional flag to return average FST for whole input region
#' @param extended optional flag to also return numerator and denominator terms for per-SNP FST
#' @return
#' \itemize{
#'   \item region = TRUE .. average FST over region
#'   \item region = FALSE, extended = FALSE .. a vector of FST per marker
#'   \item region = FALSE, extended = TRUE .. a matrix with numerator and denominator terms of FST, as well per marker FST
#' }
getFstAlleleCounts <- function(p, region = FALSE, extended = FALSE){

    if(region & extended) stop("'region' & 'extended' flags can't be used together")

    ## set up helper terms
    r <- dim(p)[[2]] ## number of populations
    u <- dim(p)[[3]] ## number of alleles
    nI <- rowSums(p, dims = 2) ## sample size (number of alleles) per SNP and population,
    nIC <- nI - nI^2 / rowSums(nI)
    nC <- rowSums(nIC) / (r - 1)

    pI <- p / as.vector(nI) ## frequency of each allele per SNP and population
    pBar <- apply(pI, 3, function(x){
        rowSums(x * nI) / rowSums(nI)
    }) ## average frequency of each allele over all populations per SNP

    msp1 <- sapply(1:u, function(x){
        rowSums(nI * (pI[,, x] - pBar[, x])^2)
    })
    msp <- msp1 / (r - 1) ## mean squares among populations

    msg1 <- sapply(1:u, function(x){
        rowSums(nI * pI[,, x] * (1 - pI[,, x]))
    })
    msg <- msg1 / rowSums(nI - 1) ## mean squares within populations

    ## build final reults
    num <- rowSums(msp - msg) ## numerator term, summed over all alleles
    denom <- rowSums(msp + (nC - 1) * msg)

    if(region){
        theta <- sum(num) / sum(denom)
    } else {
        theta <- num / denom
    }
    if(extended){
        theta <- cbind(num, denom, theta)
    }
    return(theta)
}


#' F3 test
#'
#' Takes an array of allele counts input and does f3 test as in
#' Patterson et al. 2012 on specified input populations; corresponds
#' to "f3 outgroup" statistic if 'test' is an outgroup population
#'
#' @param p allele counts array, dimensions SNPs x individuals x 2
#' @param idxM matrix of dimensions 1 x 3 with population labels for test
#' configuration f3(test;ref1,ref2)
#' @param blockIdx index vector of chromosome blocks for jackknife
#' @return a data frame with f3 results
#' \itemize{
#'   \item p1, p2, p3  .. test configuration
#'   \item f3 .. estimate
#'   \item se, Z .. standard error and Z score from block jackknife
#'   \item nSites .. number of informative SNPs used in the test
#' }
doF3Test <- function(p, idxM, blockIdx){

    ## first some helper data
    p <- p[, idxM, ]
    K <- t(apply(p, 1, rowSums)) ## total counts per population
    f <- p[, , 2] / K ## frequency of allele 2 per population
    idx <- rowSums(f[, c(1, 2)] == 0) <= 1 & rowSums(f[, c(1, 3)] == 0) <= 1 & rowSums(f[, c(1, 2)] == 1) <= 1 & rowSums(f[, c(1, 3)] == 1) <= 1 ## only SNPs polymorphic in p1/p2 and p1/p3
    p <- p[idx,,]
    K <- K[idx,]
    f <- f[idx,]
    blockIdx <- blockIdx[idx]

    H <- (p[, 1, 1] * p[, 1, 2]) / (K[, 1] * (K[, 1] - 1)) ## marker heterozygosity for test population
    a <- (f[, 1] - f[, 2]) * (f[, 1] - f[, 3]) - H / K[, 1] ## f3 statistic numerator terms; denominator is H (unbiased estimator of heterozygosity in testPop)

    N <- length(a) ## number of observations
    m <- fastTable(blockIdx) ## group sizes
    h <- N / m  ## total observations / group sizes
    g <- length(m) ## number of groups
    h1 <- 1 / (h - 1) ## multiplication factor in variance calculation

    ## now build the test
    num <- sum(a)
    denom <- 2 * sum(H)
    stat <- num / denom

    ## do jackknife
    aBlock <- rowsum(a, blockIdx) ## contribution to sum in numerator from each block
    bBlock <- 2 * rowsum(H, blockIdx) ## contribution to sum in denominator from each block
    statJ <- (num - aBlock) / (denom - bBlock) ## stat value, leaving out contribution of each block j
    pseudoStatJ <- h * stat - (h - 1) * statJ ## pseudo values of stat (below eq 8 in Busing et al, 1999)
    statJK <- g * stat - sum((1 - m / N) * statJ) ##  delete - mj jackknife estimator of stat (eq 8)
    varJK <- 1 / g * sum(h1 * (pseudoStatJ - statJK)^2)
    se <- sqrt(varJK)

    res <- data.frame(p1 = idxM[, 1], p2 = idxM[, 2], p3 = idxM[, 3], f3 = stat, se = se, Z = stat / se, nSites = N, stringsAsFactors = FALSE)
    return(res)
}


#' D test
#'
#' Takes a matrix of allele frequencies as input and does D test as in
#' Patterson et al. 2012 on specified input populations
#'
#' @param p allele counts array, dimensions SNPs x individuals x 2
#' @param idxM matrix of dimensions 1 x 4 with population labels for test
#' configuration D(p1,p2)(p3,p4)
#' @param blockIdx index vector of chromosome blocks for jackknife
#' @return a data frame with D results
#' \itemize{
#'   \item p1, p2, p3, p4  .. test configuration
#'   \item D .. estimate
#'   \item se, Z .. standard error and Z score from block jackknife
#'   \item nSites .. number of informative SNPs used in the test
#' }
doDTest <- function(p, idxM, blockIdx){

    ## first some helper data
    p <- p[, idxM]
    idx <- !(rowSums(p[, 1:2]) %in% c(0, 2) | rowSums(p[, 3:4]) %in% c(0, 2)) ## only SNPs polymorphic in p1/p2 and p3/p4
    p <- p[idx, ]
    blockIdx <- blockIdx[idx]

    a <- (p[, 1] - p[, 2]) * (p[, 3] - p[, 4]) ## numerator terms per SNP
    b <- (p[, 1] + p[, 2] - 2 * p[, 1] * p[, 2]) * (p[, 3] + p[, 4] - 2 * p[, 3] * p[, 4]) ## denominator terms per SNP

    N <- length(a) ## number of observations
    m <- fastTable(blockIdx) ## group sizes
    h <- N / m  ## total observations / group sizes
    g <- length(m) ## number of groups
    h1 <- 1 / (h - 1) ## multiplication factor in variance calculation


    ## now build the test
    num <- sum(a)
    denom <- sum(b)
    stat <- num / denom

    ## do jackknife
    aBlock <- rowsum(a, blockIdx)  ## contribution to sum in numerator from each block
    bBlock <- rowsum(b, blockIdx)  ## contribution to sum in denominator from each block
    statJ <- (num - aBlock) / (denom - bBlock) ## stat value, leaving out contribution of each block j
    pseudoStatJ <- h * stat - (h - 1) * statJ ## pseudo values of stat (below eq 8 in Busing et al, 1999)
    statJK <- g * stat - sum((1 - m / N) * statJ) ##  delete - mj jackknife estimator of stat (eq 8)
    varJK <- 1 / g * sum(h1 * (pseudoStatJ - statJK)^2)
    se <- sqrt(varJK)

    res <- data.frame(p1 = idxM[,1], p2 = idxM[,2], p3 = idxM[,3], p4 = idxM[,4], D = stat, se = se, Z = stat / se, nSites = N, stringsAsFactors = FALSE)
    return(res)
}


########################
## plotting functions ##
########################

#' Plot f3/D stat against population ID
#'
#' Function to plot results from D/f3 stat with possible groupings;
#' order of populations will be same as input order for default settings
#'
#' @import ggplot2
#' 
#' @param value vector of estimates
#' @param se vector of standard errors
#' @param label vector of population labels
#' @param groupId vector of group labels
#' @param groupColors named vector of colors for each group; order of groupings is taken from this
#' @param intercept value for lines indicating desired statistic values (default: 0)
#' @param z Z-score cutoffs for whiskers (default: 1, 3)
#' @param size size for plot symbols (default: 2)
#' @param shape shape for plot symbols (default: 23)
#' @param labSize size for axis and facet labels (default: 8)
#' @param grouped combine observations in groups for plotting; order of groups given by groupColor (default: FALSE)
#' @param orderValue reorder observations by decreasing estimate; forces grouped = FALSE (default: FALSE)
#' @param horizontal plot populations on the x-axis (default: TRUE)
#' @param showLegend show color legend for groups (default: TRUE)
#' @return a ggplot2 plot object
#'

plotFStat <- function(value, se, label, groupId, groupColors, z = c(1, 3), intercept = 0, size = 2, shape = 23, labSize = 8, grouped = FALSE, orderValue = FALSE, horizontal = TRUE, showLegend = TRUE){

    ## prepare plotting data.frame
    d <- data.frame(label = label, groupId = groupId, value = value, se1 = z[1] * se, se2 = z[2] * se)
    if(orderValue){
        grouped <- FALSE ## force grouped to FALSE if ordered values are requested
        d <- d[order(-d$value),]
    }
    d$label <- factor(d$label, levels = unique(d$label))
    d$groupId <- factor(d$groupId, levels = names(groupColors))

    ## set up plot
    o1 <- theme(legend.position = "right")
    if(!showLegend){
        o1 <- theme(legend.position = "none")
    }
    if(grouped){
        if(horizontal){
            o2 <- facet_grid(. ~ groupId, space = "free", scales = "free_x")
        } else {
            o2 <- facet_grid(groupId ~ ., space = "free", scales = "free_y")
        }
    } else {
        o2 <- NULL
    }
    if(horizontal){
        p <- ggplot(d, aes(x = label, y = value, fill = groupId, color = groupId))
        p + geom_hline(aes(yintercept = 0), color = "grey", size = 0.25) + geom_hline(yintercept = intercept, color = "grey20", size = 0.25, linetype = "dashed") + geom_point(shape = shape, alpha = 0.7, size = size) + geom_errorbar(aes(ymin = value - se2, ymax = value + se2), width = 0, size = 0.4) + geom_errorbar(aes(ymin = value - se1, ymax = value + se1), width = 0, size = 0.8)  + scale_colour_manual(name = "Group", values = groupColors) + scale_fill_manual(name = "Group", values = groupColors) + labs(y = "Estimate", x = "Population") + theme_bw() + theme(panel.grid.minor=element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 90, size = labSize, hjust = 1, vjust = 0.5), axis.text.y = element_text(size = labSize), strip.background = element_blank(), strip.text.x = element_text(size = labSize, angle = 90, hjust = 0)) + o1 + o2
    } else {
        p <- ggplot(d, aes(x = value, y = label, fill = groupId, color = groupId))
        p + geom_hline(aes(xintercept = 0), color = "grey", size = 0.25) + geom_vline(xintercept = intercept, color = "grey20", size = 0.25, linetype = "dashed") + geom_point(shape = shape, alpha = 0.7, size = size) + geom_errorbarh(aes(xmin = value - se2, xmax = value + se2), height = 0, size = 0.4) + geom_errorbarh(aes(xmin = value - se1, xmax = value + se1), height = 0, size = 0.8)  + scale_colour_manual(name = "Group", values = groupColors) + scale_fill_manual(name = "Group", values = groupColors) + labs(x = "Estimate", y = "Population") + theme_bw() + theme(panel.grid.minor=element_blank(), panel.grid.major = element_blank(), axis.text.x = element_text(angle = 90, size = labSize, hjust = 1, vjust = 0.5), axis.text.y = element_text(size = labSize), strip.background = element_blank(), strip.text.y = element_text(size = labSize, angle = 0, hjust = 0)) + o1 + o2
    }
}



#' Plot pairs of f stats
#'
#' Function to plot pairwise D/f3 stats
#'
#' @import ggplot2
#' 
#' @param x vector of estimates for x axis
#' @param y vector of estimates for y axis
#' @param seX vector of standard errors for x axis
#' @param seY vector of standard errors for y axis
#' @param groupId vector of group labels
#' @param groupColors named vector of colors for each group; order of groupings is taken from this
#' @param label vector of text labels for observations (default: no labels)
#' @param z Z-score cutoffs for whiskers (default: 1, 3)
#' @param size size for plot symbols (default: 2)
#' @param shape shape for plot symbols (default: 23)
#' @param alpha transparency for plot symbols (default: 0.5)
#' @param labSize size for axis and facet labels (default: 8)
#' @param alphaZ transparency for Z-score whiskers (default: 0.5)
#' @param showLegend show color legend for groups (default: TRUE)
#' @return a ggplot2 plot object
plotFPairs <- function(x, y, seX, seY, groupId, groupColors, label = NULL, z = 3, size = 2, shape = 23, alpha = 0.5, labSize = 8, alphaZ = 0.5, showLegend = TRUE){

    ## prepare plotting data.frame
    d <- data.frame(x = x, y = y, seX = z * seX, seY = z * seY, groupId = groupId)
    d$groupId <- factor(d$groupId, levels = names(groupColors))

    ## set up plot
    o1 <- theme(legend.position = "right")
    if(!showLegend){
        o1 <- theme(legend.position = "none")
    }

    if(!is.null(label)){
        d$label <- label
        o2 <- geom_text(aes(x = x, y = y, label = label), data = d, size = 2.5)
    } else {
        o2 <- NULL
    }
    p <- ggplot(d, aes(x = x, y = y, fill = groupId, color = groupId))
    p + geom_abline(intercept = 0, slope = 1e10, size = 0.25) + geom_abline(intercept = 0, slope = 0, size = 0.25) + geom_abline(intercept = 0, slope = 1, color = "grey", size = 0.25) + geom_point(shape = shape, alpha = alpha, size = size, shape = shape) + geom_errorbar(aes(ymin = y - seY, ymax = y + seY), width = 0, size = 0.25, alpha = alphaZ) + geom_errorbarh(aes(xmin = x - seX, xmax = x + seX), height = 0, size = 0.25, alpha = alphaZ) + scale_colour_manual(name = "Group", values = groupColors) + scale_fill_manual(name = "Group", values = groupColors) + theme_bw() + theme(panel.grid.minor=element_blank(), panel.grid.major = element_blank()) + o1 + o2
}
