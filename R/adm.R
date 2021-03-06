#' likelihood function for ADMIXTURE projections
#'
#' \code{llAdmixture} calculates the likelihood of the genotypes
#' given the Q matrix and P matrix.
#' genotype vector is coded as 0,1,2 and has to match coding from P matrix
#' Equation (2) from Alexander et al. Genome Res. 2009 19: 1655-1664
#'
#' @param qM The Q matrix of cluster proportions from ADMIXTURE,
#' dimensions individuals x components
#' @param pM The P matrix of ancestral cluster frequencies from ADMIXTURE,
#' dimensions n SNPs x components
#' @param gt genotype vector
#' @return log-likelihood
llAdmixture <- function(qM, pM, gt){

    qM <- qM / sum(qM) ## transform values to ensure sum(qM) == 1
    pM <- t(pM)
    p1 <- colSums(qM * pM)
    p2 <- colSums(qM * (1 - pM))
    p11 <- log(p1) * gt
    p21 <- log(p2) * (2 - gt)

    res <- sum(p11 + p21)
    -res ## optim mininizes by default
}


#' project genotypes on ADMIXTURE P matrix
#'
#' \code{doAdmixtureProjection} projet a genotype vector on a
#' given P matrix. Genotype vector is coded as 0,1,2
#' and has to match coding from P matrix
#'
#' @param gt genotype vector
#' @param pM The P matrix of ancestral cluster frequencies from ADMIXTURE,
#' dimensions n SNPs x components
#' @return a vector with cluster proportions
doAdmixtureProjection <- function(gt, pM){

    k <- ncol(pM) ## number of K from columns of P matrix
    q0 <- rep(1/k, k) ## starting values for q
    r <- optim(q0, llAdmixture, pM = pM, gt = gt, method = "L-BFGS-B", lower = 1e-5, upper = 1 - 1e-5)
    estimate <- r$par / sum(r$par) ## rescale estimates to sum 1
    estimate
}

#' plot ADMIXTURE results
#'
#' \code{plotAdmixture} generates classic ADMIXTURE barplots for ancestry proportions
#' with various customizations. Input has to be in long format, i.e. each combination
#' of individual / cluster / proportion on a separate line
#'
#' @import ggplot2
#' @import dplyr
#'
#' @param sampleId vector of sample IDs
#' @param popId vector of population IDs for grouping of samples
#' @param k vector of cluster indices (integer)
#' @param value vector of cluster proportions (integer)
#' @param colors vector of colors for each of the K clusters
#' @param kOrder vector of ordering for the K clusters
#' @param width vector of bar widths for cluster proportions
#' @param alpha vector of transparency for cluster proportions
#' @param popLabels use population IDs instead of sample IDs for x axis (logical)
#' @param labColors vector of colors to use for x axis labels
#' @param rot angle for x axis labels (integer)
#' @param showLegend display legend for cluster ID and color (logical)
#' @return a ggplot2 plot object
plotAdmixture <- function(sampleId, popId, k, value, colors, kOrder = 1:max(k), width = 1, alpha = 1, popLabels = TRUE, labColors = "black", rot = 0, showLegend = FALSE){

    ## prepare plotting dataframe
    d <- data.frame(sampleId = sampleId, popId = popId, k = k, value = value)
    idxP <- levels(popId)
    d$width <- width
    d$alpha <- factor(alpha, levels = sort(unique(alpha)))
    d$k <- factor(d$k, levels = kOrder)
    d <- d[order(d$sampleId, d$popId, d$k),]
    x <- d$width[!duplicated(d$sampleId)]
    d$xend <- rep(cumsum(x), each = max(k)) + 0.5 ## end x coordinate for each sample
    idx <- diff(c(1, x)) != 0 ## index of changes in width
    x[idx] <- x[idx] / 2 + 0.5
    x1 <- cumsum(x)
    d$x <- rep(x1, each = max(k)) ## center x coordinate for each sample

    ## get x & xend positions for each population
    d1 <- filter(d, k == 1) %>% group_by(popId) %>% summarise(x = mean(x), xend = max(xend))

    ## set up labels
    if(rot == 0){
        hjust <- 0.5
        vjust <- 1
    } else {
        hjust <- 1
        vjust <- 0.5
    }

    p1 <- geom_text(aes(x = x, y = -0.05, label = sampleId, fill = NULL), colour = "black", size = 2, angle = rot, hjust = hjust, vjust = vjust, data = d)
    if(popLabels){
        p1 <- geom_text(aes(x = x, y = -0.05, label = popId, fill = NULL), colour = labColors, size = 2, angle = rot, hjust = hjust, vjust = vjust, data = d1)
    }
    o <- theme(panel.border = element_blank(), panel.grid.major = element_blank(), panel.grid.minor = element_blank(), strip.background = element_rect(fill = NA, colour = NA), strip.text = element_text(colour = "white", face = "bold"), axis.text.x = element_blank(), axis.ticks = element_blank(), axis.ticks.length = grid::unit(0, "cm"), plot.background = element_rect(fill = "transparent", colour = NA))
    o1 <- theme(legend.position = "top", legend.box = "horizontal")
    if(!showLegend){
        o1 <- theme(legend.position = "none")
    }

    ## prepare plot
    p <- ggplot(d, aes(x = x, y = value, fill = k, colour = k))
    p + geom_bar(aes(width = width, alpha = alpha), stat = "identity", size = 0.05) + p1 + geom_segment(aes(x = xend, xend = xend, y = 0, yend = 1, fill = NA), colour = "black", size = 0.1, data = d1) + scale_colour_manual(values = colors) + scale_fill_manual(values = colors) + scale_alpha_manual(values = unique(sort(alpha)), guide = FALSE) + scale_y_continuous(breaks = NULL, limits = c(-0.5, 1.01)) + theme_bw() + labs(x = "", y = "") + o + o1 + geom_rect(aes(xmin = 0.5, ymin = 0, xmax = max(xend), ymax = 1), fill = NA, colour = "black", size = 0.1)
}
