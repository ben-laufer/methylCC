#' @title Finding differentially methylated regions
#' 
#' @description This function use flow sorted array 
#' reference methylomes for either blood, cordblood, 
#' or brain to identify differentially methylated regions.  
#'
#' @param verbose TRUE/FALSE argument specifying if verbose
#' messages should be returned or not. Default is TRUE.
#' @param gr_target Default is NULL. However, the user 
#' can provide a GRanges object from the \code{object} 
#' in \code{estimatecc}. Before starting the procedure to 
#' find differentially methylated regions, the intersection
#' of the \code{gr_target} and GRanges object from the 
#' reference methylomes (\code{FlowSorted.Blood.450k}). 
#' @param include_cpgs TRUE/FALSE. Should individual CpGs
#' be returned. Default is FALSE. 
#' @param include_dmrs TRUE/FALSE. Should differentially 
#' methylated regions be returned. Default is TRUE. User
#' can turn this to FALSE and search for only CpGs. 
#' @param num_cpgs The max number of CpGs to return 
#' for each cell type. Default is 50.
#' @param num_regions The max number of DMRs to return 
#' for each cell type. Default is 50. 
#' @param bumphunter_beta_cutoff The \code{cutoff} threshold 
#' in \code{bumphunter()} in the \code{bumphunter} package. 
#' @param dmr_up_cutoff A cutoff threshold for identifying 
#' DMRs that are methylated in one cell type, but not in the 
#' other cell types. 
#' @param dmr_down_cutoff A cutoff threshold for identifying 
#' DMRs that are not methylated in one cell type, but 
#' methylated in the other cell types.
#' @param dmr_pval_cutoff  A cutoff threshold for the p-values 
#' when identifying DMRs that are methylated in one cell 
#' type, but not in the other cell types (or vice versa). 
#' @param cpg_pval_cutoff A cutoff threshold for the p-values 
#' when identifying differentially methylated CpGs that are
#' methylated in one cell type, but not in the other cell
#' types (or vice versa). 
#' @param cpg_up_dm_cutoff A cutoff threshold for identifying 
#' differentially methylated CpGs that are methylated in 
#' one cell type, but not in the other cell types. 
#' @param cpg_down_dm_cutoff A cutoff threshold for identifying 
#' differentially methylated CpGs that are not methylated in 
#' one cell type, but are methylated in the other cell types.  
#' @param pairwise_comparison TRUE/FAlSE of whether all pairwise
#' comparisons (e.g. methylated in Granulocytes and Monocytes, 
#' but not methylated in other cell types). Default if FALSE. 
#' @param mset_train_flow_sort Default is NULL and will select 
#' select \code{"FlowSorted.Blood.450k"}. Alternatively, the user
#' can specify another existing dataset \code{c("FlowSorted.Blood.EPIC",
#' "FlowSorted.CordBloodCombined.450k", "FlowSorted.CordTissueAndBlood.EPIC",
#' "FlowSorted.DLPFC.450k")}. Additionally, a user can provide a 
#' \code{MethylSet} object after processing the 
#' \code{FlowSorted.Blood.450k} dataset. The default
#' normalization is \code{preprocessIllumina()}.
#' 
#' @return A list of data frames and GRanges objects.
#' 
#' @import methylCC
#' @import minfi 
#' @import GenomicRanges
#' @import ExperimentHub
#' @import FlowSorted.Blood.450k
#' @import FlowSorted.DLPFC.450k
#' @import FlowSorted.CordBloodCombined.450k
#' @import FlowSorted.Blood.EPIC
#' @import IlluminaHumanMethylation450kmanifest
#' @import IlluminaHumanMethylationEPICmanifest
#' @import IlluminaHumanMethylationEPICanno.ilm10b2.hg19
#' @importFrom Biobase pData
#' @importFrom bumphunter clusterMaker loessByCluster bumphunter 
#' @importFrom genefilter rowttests
#' @importFrom plyranges arrange 
#' @importFrom S4Vectors queryHits
#' @importFrom stats model.matrix
#' @importFrom utils head
#' @importFrom glue glue
#' @importFrom magrittr %>%
.find_dmrs <- function(verbose = TRUE, gr_target = NULL,
                       include_cpgs = FALSE, include_dmrs = TRUE,
                       num_cpgs = 50, num_regions = 50, 
                       bumphunter_beta_cutoff = 0.2, 
                       dmr_up_cutoff = 0.5, dmr_down_cutoff = 0.4,
                       dmr_pval_cutoff = 1e-11, cpg_pval_cutoff = 1e-08,
                       cpg_up_dm_cutoff = 0, cpg_down_dm_cutoff = 0, 
                       pairwise_comparison = FALSE,
                       mset_train_flow_sort = NULL) {
  
  if(mset_train_flow_sort == "FlowSorted.Blood.450k"){
    dataset <- mset_train_flow_sort
    mset_train_flow_sort <- FlowSorted.Blood.450k
    mset_train_flow_sort <- mset_train_flow_sort %>%
      updateObject() %>%
      preprocessIllumina() %>% 
      mapToGenome(mergeManifest = FALSE)
    
    IDs <- c("Gran", "CD4T", "CD8T", "Bcell", "Mono", "NK")
    
    # remove outliers
    mset_train_flow_sort <- mset_train_flow_sort[, 
                                                 pData(mset_train_flow_sort)$Sample_Name != "CD8+_105"]
    
  }else if(mset_train_flow_sort == "FlowSorted.Blood.EPIC"){
    dataset <- mset_train_flow_sort
    mset_train_flow_sort <- ExperimentHub::ExperimentHub()[["EH1136"]] %>%
      updateObject() %>%
      preprocessIllumina() %>%
      mapToGenome(mergeManifest = FALSE)
    
    IDs <- c("Neu", "NK", "Bcell" , "CD4T", "CD8T", "Mono")
    
  }else if(mset_train_flow_sort == "FlowSorted.CordTissueAndBlood.EPIC"){
    if(!require(FlowSorted.CordTissueAndBlood.EPIC)){
      install.packages(paste0("https://karnanilab.com/Tools/",
                              "FlowSorted.CordTissueAndBlood.EPIC/",
                              "FlowSorted.CordTissueAndBlood.EPIC_1.0.1.tar.gz"),
                       repos = NULL, type = "source")}
    library(FlowSorted.CordTissueAndBlood.EPIC)
    
    dataset <- mset_train_flow_sort
    mset_train_flow_sort <- FlowSorted.CordTissueAndBlood.EPIC %>% 
      updateObject() %>%
      preprocessIllumina() %>%
      mapToGenome(mergeManifest = FALSE)
    
    IDs <- c("CD8T", "CD4T", "NK", "Bcell", "Mono", "Gran")
    
  }else if(mset_train_flow_sort == "FlowSorted.CordBloodCombined.450k"){
    dataset <- mset_train_flow_sort
    mset_train_flow_sort <- ExperimentHub::ExperimentHub()[["EH2256"]] %>%
      updateObject() %>%
      preprocessIllumina() %>%
      mapToGenome(mergeManifest = FALSE)
    
    IDs <- c("CD8T", "CD4T", "NK", "Bcell", "Mono", "Gran", "nRBC")
    
  }else if(mset_train_flow_sort == "FlowSorted.DLPFC.450k"){
    dataset <- mset_train_flow_sort
    mset_train_flow_sort <- FlowSorted.DLPFC.450k
    mset_train_flow_sort <- mset_train_flow_sort %>%
      updateObject() %>%
      preprocessIllumina() %>%
      mapToGenome(mergeManifest = FALSE)
    
    IDs <- c("NeuN_pos", "NeuN_neg")
    
  }else{
    # remove outliers
    dataset <- "FlowSorted.Blood.450k"
    mset_train_flow_sort <- mset_train_flow_sort[, 
                                                 pData(mset_train_flow_sort)$Sample_Name != "CD8+_105"]
    IDs <- c("Gran", "CD4T", "CD8T", "Bcell", "Mono", "NK")
  }
  
  # create training object to identify DMRs
  mset_train_flow_sort <- mset_train_flow_sort[, 
                                               (pData(mset_train_flow_sort)$CellType %in% IDs) ]
  
  # find celltype specific regions using only overlap CpGs in target object
  if(!is.null(gr_target)){ 
    # which of the 450K CpGs overlap with the target CpGs
    zz <- findOverlaps(granges(mset_train_flow_sort), gr_target) 
    mset_train_flow_sort <- mset_train_flow_sort[queryHits(zz), ]
    if(verbose){
      mes <- "[estimatecc] gr_target is not null. Using %s overlapping CpGs."
      message(sprintf(mes, nrow(mset_train_flow_sort)))
    }
  }  
  
  # extract beta values, phenotypic information and GRanges objects
  pd <- as.data.frame(pData(mset_train_flow_sort))
  gr <- granges(mset_train_flow_sort)
  p_beta <- getBeta(mset_train_flow_sort, type = "Illumina") # beta values
  
  if(dataset == "FlowSorted.Blood.450k"){
    colnames(p_beta) = pd$Sample_Name = rownames(pd) = 
      gsub("\\+","", pd$Sample_Name)
  }else if(dataset == "FlowSorted.Blood.EPIC" |
           dataset == "FlowSorted.CordBlood.EPIC" |
           dataset == "FlowSorted.CordBloodCombined.450k"){
    colnames(p_beta) = pd$Sample_Name = rownames(pd) =
      paste(pd$CellType, pd$Sample_Name, pd$Slide, sep="_")
  }else if(dataset == "FlowSorted.DLPFC.450k"){
    colnames(p_beta) = pd$Sample_Name = rownames(pd) =
      paste(pd$CellType, pd$SampleID, sep="_")
  }
  
  cell <- factor(pd$CellType, levels = IDs)
  cell_levels <- levels(cell)
  
  # extract chromosome and position information for each probe in 
  #   450k array (need this for regions)
  chr <- as.character(seqnames(gr))
  pos <- start(gr)
  cl <- clusterMaker(chr, pos) # Create clusters using clusterMaker()
  
  # define design matrix to search for DMRs
  xmat = cbind(rep(1, length(cell)), model.matrix(~cell - 1))
  colnames(xmat) = c("Intercept", cell_levels)
  
  if(pairwise_comparison){
    all_poss = as.matrix(expand.grid(c(0,1), c(0,1), c(0,1), 
                                     c(0,1), c(0,1), c(0,1)))
    # remove the cases containing all methylated or unmethylated. 
    all_poss = all_poss[2:32,] 
    all_poss <- (all_poss == TRUE)
    colnames(all_poss) <- cell_levels
  } else { 
    all_poss = diag(length(cell_levels))
    all_poss <- (all_poss == TRUE)
    colnames(all_poss) <- cell_levels
  }
  
  regions_all <- GRanges() 
  zmat <- c() # regions_all, will contain all celltype-specific DMRs
  for(ind in seq_len(nrow(all_poss))){
    if(verbose){
      if(include_dmrs & include_cpgs){
        mes <- "[estimatecc] Searching for %s cell type-specific 
                regions and CpGs."
        message(sprintf(mes, paste(cell_levels[all_poss[ind,]], collapse=",")))
      } 
      if(include_dmrs & !include_cpgs) {
        mes <- "[estimatecc] Searching for %s cell type-specific regions."
        message(sprintf(mes, paste(cell_levels[all_poss[ind,]], collapse=",")))
      }
      if(!include_dmrs & include_cpgs) {
        mes <- "[estimatecc] Searching for %s cell type-specific CpGs"
        message(sprintf(mes, paste(cell_levels[all_poss[ind,]], collapse=",")))
      }
    }
    
    x_ind = cbind("Intercept" = xmat[, "Intercept"],
                  "cellTypes" = rowSums(
                    as.matrix(xmat[, cell_levels[all_poss[ind,]] ],
                              ncols = length(cell_levels[all_poss[ind,]]))))
    
    if(!include_dmrs){ 
      gr_regions_up <- GRanges()
      gr_regions_down <- GRanges()
    }
    
    if(include_dmrs){
      bumps = bumphunter(object = p_beta, design = x_ind, 
                         chr = chr, pos = pos, cluster = cl, 
                         cutoff = bumphunter_beta_cutoff, 
                         B = 0, smooth = FALSE, 
                         smoothFunction = loessByCluster)
      
      # y_regions are the beta values collapsed (CpGs averaged) by regions 
      # from bumphunter
      y_regions <- t(apply(bumps$table[,7:8], 1, function(z){
        colMeans(p_beta[(z[1]):(z[2]),,drop=FALSE]) } ))
      
      tmp <- rowttests(y_regions,factor(x_ind[,"cellTypes"]))
      bumps$table$p.value <- tmp$p.value
      bumps$table$dm <- tmp$dm 
      bumps$table$dmr_up_max_diff <- 
        apply(abs(sweep(y_regions, 2, x_ind[,"cellTypes"], FUN = "-")), 1, max)
      bumps$table$dmr_down_max_diff <- 
        apply(abs(sweep(y_regions, 2, (1 - x_ind[,"cellTypes"]), FUN = "-")), 
              1, max)
      
      # # Only include region with more than 1 CpG (L > 1)
      # #       OR only 1 CpG in region if no other larger regions possible
      L = dm <- NULL 
      keep_ind_regions <- (bumps$table$L > 1 | 
                             (bumps$table$L==1 & bumps$table$clusterL == 1)) & 
        (bumps$table$p.value < dmr_pval_cutoff)  # ideally less than 1e-11
      
      bump_mat_up <- bumps$table[keep_ind_regions & bumps$table$dm < 0 &
                                   # ideally less than 0.6
                                   bumps$table$dmr_up_max_diff<dmr_up_cutoff,] 
      bump_mat_up <- bump_mat_up[order(-bump_mat_up$L, bump_mat_up$dm), ]
      if(nrow(bump_mat_up) > 0){
        gr_regions_up <- makeGRangesFromDataFrame(bump_mat_up, 
                                                  keep.extra.columns=TRUE)
        mcols(gr_regions_up)$dmr_status <- rep("DMR", length(gr_regions_up))
        gr_regions_up <- gr_regions_up[, names(mcols(gr_regions_up)) %in% 
                                         c("indexStart", "indexEnd", "L", "dm", "p.value", 
                                           "dmr_status", "dmr_up_max_diff")]
        names(mcols(gr_regions_up))[
          names(mcols(gr_regions_up)) == "dmr_up_max_diff"] <- "dmr_max_diff"
        
        gr_regions_up <- gr_regions_up %>% arrange(-L, dm) %>% 
          head(num_regions)
      } else {
        gr_regions_up <- GRanges()
      }
      
      bump_mat_down <- bumps$table[(keep_ind_regions) & bumps$table$dm > 0 & 
                                     bumps$table$dmr_down_max_diff < 
                                     dmr_down_cutoff,] # ideally less than 0.8
      bump_mat_down <- bump_mat_down[order(-bump_mat_down$L, 
                                           -bump_mat_down$dm), ]
      if(nrow(bump_mat_down) > 0){
        gr_regions_down <- makeGRangesFromDataFrame(bump_mat_down, 
                                                    keep.extra.columns=TRUE)
        mcols(gr_regions_down)$dmr_status <- 
          rep("DMR", length(gr_regions_down))
        gr_regions_down <- gr_regions_down[, names(mcols(gr_regions_down)) %in%
                                             c("indexStart", "indexEnd", "L", "dm", "p.value", 
                                               "dmr_status", "dmr_down_max_diff")]
        names(mcols(gr_regions_down))[names(mcols(gr_regions_down)) 
                                      == "dmr_down_max_diff"] <- "dmr_max_diff"
        gr_regions_down <- gr_regions_down %>% 
          arrange(-L, -dm) %>% 
          head(num_regions)
      } else {
        gr_regions_down <- GRanges()
      }
    }  
    
    if(include_cpgs){
      tstats <- rowttests(p_beta, factor(x_ind[,"cellTypes"]))
      tstats <- tstats[(tstats[, "p.value"] < cpg_pval_cutoff),] 
      
      tstats_up <- tstats[order(tstats[, "dm"], decreasing = FALSE), ]
      # at a min should be less than 0
      tstats_up <- tstats_up[tstats_up$dm < cpg_up_dm_cutoff,] 
      
      probe_keep <- rownames(tstats_up)[seq_len(min(nrow(tstats_up), 
                                                    num_cpgs))]
      if(length(probe_keep) > 0){
        gr_probe <- granges(mset_train_flow_sort[probe_keep,])
        mcols(gr_probe) <- tstats[probe_keep, c("dm", "p.value")]
        mcols(gr_probe)$L <- rep(1, length(probe_keep))
        mcols(gr_probe)$indexStart <- match(probe_keep,
                                            rownames(mset_train_flow_sort))
        mcols(gr_probe)$indexEnd <- match(probe_keep, 
                                          rownames(mset_train_flow_sort))
        mcols(gr_probe)$dmr_status <- rep("CpG", length(gr_probe))
        gr_regions_up <- unique(c(gr_regions_up, 
                                  gr_probe[,c("indexStart", "indexEnd", 
                                              "L", "p.value", "dm", 
                                              "dmr_status")]))
        gr_regions_up <- gr_regions_up %>% arrange(-L, dm) %>% 
          head(num_regions)
      } 
      
      tstats_down <- tstats[order(tstats[, "dm"], decreasing = TRUE), ]
      # at a min should be greater than 0
      tstats_down <- tstats_down[tstats_down$dm > cpg_down_dm_cutoff,] 
      probe_keep <- rownames(tstats_down)[seq_len(min(nrow(tstats_down), 
                                                      num_cpgs))]
      if(length(probe_keep) > 0){
        gr_probe <- granges(mset_train_flow_sort[probe_keep,])
        mcols(gr_probe) <- tstats[probe_keep, c("dm", "p.value")]
        mcols(gr_probe)$L <- rep(1, length(probe_keep))
        mcols(gr_probe)$indexStart <- match(probe_keep,
                                            rownames(mset_train_flow_sort))
        mcols(gr_probe)$indexEnd <- match(probe_keep, 
                                          rownames(mset_train_flow_sort))
        mcols(gr_probe)$dmr_status <- rep("CpG", length(gr_probe))
        gr_regions_down <- unique(c(gr_regions_down, 
                                    gr_probe[,c("indexStart", "indexEnd", 
                                                "L", "p.value", "dm", 
                                                "dmr_status")]))
        gr_regions_down <- gr_regions_down %>% 
          arrange(-L, -dm) %>% 
          head(num_regions)
      } 
    }
    
    mcols(gr_regions_up)$status <- rep("Up", length(gr_regions_up))
    mcols(gr_regions_down)$status <- rep("Down", length(gr_regions_down))
    bump_mat_all <- c(gr_regions_up, gr_regions_down)
    mcols(bump_mat_all)$cellType <- rep(paste(cell_levels[all_poss[ind,]], 
                                              collapse=","), 
                                        length(bump_mat_all)) 
    
    if(verbose){
      if(include_dmrs & include_cpgs){
        mes <- "[estimatecc] Found %s %s cell type-specific regions and CpGs."
        message(sprintf(mes, length(bump_mat_all), 
                        paste(cell_levels[all_poss[ind,]], collapse=",")))
      } 
      if(include_dmrs & !include_cpgs) {
        mes <- "[estimatecc] Found %s %s cell type-specific regions."
        message(sprintf(mes, length(bump_mat_all), 
                        paste(cell_levels[all_poss[ind,]], collapse=",")))
      }
      if(!include_dmrs & include_cpgs) {
        mes <- "[estimatecc] Found %s %s cell type-specific CpGs."
        message(sprintf(mes, length(bump_mat_all),
                        paste(cell_levels[all_poss[ind,]], collapse=",")))
      }
    }
    
    if(length(bump_mat_all) > 0){ 
      regions_all <- c(regions_all, bump_mat_all)
    }
    if(length(gr_regions_up) > 0){
      zmat <- rbind(zmat, t(replicate(min(length(gr_regions_up), num_regions), 
                                      as.numeric(all_poss[ind,]))))
    }
    if(length(gr_regions_down) > 0){
      zmat <- rbind(zmat, t(replicate(min(length(gr_regions_down), 
                                          num_regions), 
                                      as.numeric(!all_poss[ind,]))))
    }
  }
  colnames(zmat) <- cell_levels
  
  y_regions <- t(apply(
    as.data.frame(mcols(regions_all))[,seq_len(2)],1,function(ind){
      colMeans(p_beta[(ind[1]):(ind[2]),,drop=FALSE])
    }))
  
  profiles <- vapply(.splitit(cell), 
                     FUN = function(ind){ rowMeans(y_regions[,ind])}, 
                     FUN.VALUE = numeric(nrow(y_regions)))
  
  removeMe <- duplicated(regions_all)
  list(regions_all = regions_all[!removeMe,], 
       zmat = zmat[!removeMe,], 
       y_regions = y_regions[!removeMe,], 
       profiles = profiles[!removeMe,],
       cell = cell, cell_mat = all_poss, 
       cell_levels = cell_levels, pd = pd)
} 
