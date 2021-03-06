#' calculate PCA from a genotype matrix
#'
#' \code{getPcaGT} calculates PCA from a genotype matrix.
#' genotype matrix is coded as 0,1,2. includes option to infer PCA from a
#' subset of individuals and project the remaing ones.
#' loadings are calculated as in Zou et al. Hum Hered 2010 June; 70(1): 9-22
#'
#' @param gt A matrix of genotypes, dimensions SNPs x individuals
#' @param idsPca A vector of IDs for individuals to use to build PCA (default: all)
#' @param pcs Number of PCs to calculate
#' @return A list with two components
#' \itemize{
#'   \item summary .. PCs, variance explained, loadings
#'   \item raw .. raw results from svd
#' }
getPcaGT <- function(gt, idsPca = colnames(gt), pcs = 10){

    ## filter variant & missing snps in samples for building pc space
    nNonMissing <- rowSums(!is.na(gt[, idsPca]))
    idxFixed <- (rowSums(gt[, idsPca], na.rm = TRUE) / (2 * nNonMissing)) %in% c(0,1) ## fixed snps in nonmissing genotypes
    idxMissing <- rowSums(is.na(gt[, idsPca])) == length(idsPca) ## snps with all missing data
    gt <- gt[!idxMissing & !idxFixed,]

    ## center & normalize
    gtMean <- rowMeans(gt[, idsPca], na.rm = TRUE)
    gtVar <- (gtMean / 2)*(1 - gtMean / 2)
    gtStd <- sqrt(gtVar)
    gt1 <- (gt - gtMean) / gtStd
    gt1[is.na(gt1)] <- 0 ## set missing values to have mean gt (0 after normalizing)

    ## do pca
    pca <- svd(gt1[, idsPca])
    rownames(pca$u) <- rownames(gt)
    rownames(pca$v) <- idsPca

    res <- pca$v[, 1:pcs]
    colnames(res) <- paste("PC", 1:pcs, sep = "")

    ## calculate loadings for each SNP
    l <- sapply(1:ncol(pca$u), function(x){
        r <- pca$u[, x] * sqrt(pca$d[x] * gtVar)
    })

    ## variance explained
    expl <- round(100 * pca$d^2 / sum(pca$d^2), 2)[1:pcs]

    ## project if necessary
    doProjection <- !all(colnames(gt) %in% idsPca)
    if(doProjection){
        idsProj <- colnames(gt)[!(colnames(gt) %in% idsPca)]
        proj <- t(gt1[, idsProj]) %*% pca$u[, 1:pcs]
        proj <- t(t(proj) / pca$d[1:pcs])
        rownames(proj) <- idsProj
        res <- rbind(res, proj)
    }

    ## return results
    return(list(summary = list(pca = res, explained = expl, loadings = l[, 1:pcs]), raw = pca))
}


#' Fast PCA from a genotype matrix using partial SVD
#'
#' \code{getPcaGTFast} calculates PCA from a genotype matrix, using partial SVD.
#' genotype matrix is coded as 0,1,2. includes option to infer PCA from a
#' subset of individuals and project the remaing ones.
#' loadings are calculated as in Zou et al. Hum Hered 2010 June; 70(1): 9-22
#'
#' @param gt A matrix of genotypes, dimensions SNPs x individuals
#' @param idsPca A vector of IDs for individuals to use to build PCA (default: all)
#' @param pcs Number of PCs to calculate
#' @return A list with two components
#' \itemize{
#'   \item summary .. PCs
#'   \item raw .. raw results from svds
#' }
getPcaGTFast <- function(gt, idsPca = colnames(gt), pcs = 10){

    if (!requireNamespace("rARPACK", quietly = TRUE)) {
        stop("rARPACK needs to be installed for this function to work")
    }

    ## filter variant & missing snps in samples for building pca space
    nNonMissing <- rowSums(!is.na(gt[, idsPca]))
    idxFixed <- (rowSums(gt[, idsPca], na.rm = TRUE) / (2 * nNonMissing)) %in% c(0,1) ## fixed snps in nonmissing genotypes
    idxMissing <- rowSums(is.na(gt[, idsPca])) == length(idsPca) ## snps with all missing data
    gt <- gt[!idxMissing & !idxFixed,]

    ## center & normalize
    gtMean <- rowMeans(gt[, idsPca], na.rm = TRUE)
    gtStd <- sqrt((gtMean / 2)*(1 - gtMean / 2))
    gt1 <- (gt - gtMean) / gtStd
    gt1[is.na(gt1)] <- 0 ## set missing values to have mean gt (0 after normalizing)

    ## do pca
    pca <- rARPACK::svds(gt1[, idsPca], k = pcs)
    rownames(pca$u) <- rownames(gt)
    rownames(pca$v) <- idsPca

    res <- pca$v
    colnames(res) <- paste("PC", 1:pcs, sep = "")

    ## project if necessary
    doProjection <- !all(colnames(gt) %in% idsPca)
    if(doProjection){
        idsProj <- colnames(gt)[!(colnames(gt) %in% idsPca)]
        proj <- t(gt1[, idsProj]) %*% pca$u
        proj <- t(t(proj) / pca$d[1:pcs])
        rownames(proj) <- idsProj
        res <- rbind(res, proj)
    }
    return(list(summary = list(pca = res), raw = pca))
}
