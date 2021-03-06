
#' dispaly message with time stamp
#' @param msg characters; message to display
#' @export
loginfo <- function(msg) {
  timestamp <- sprintf("%s", Sys.time())
  msg <- paste0("[",timestamp, "] ", msg,"\n")
  cat(msg)
}

#' entropy of each row of the input matrix
#' @param x matrix;
mrow.entropy <- function(x)
{
  freqs <- sweep(x,1,rowSums(x),"/")
  H = - rowSums(ifelse(freqs>0,freqs* log2(freqs),0))
  return(H)
}

#' entropy of each column of the input matrix
#' @param x matrix;
mcol.entropy <- function(x)
{
  freqs <- sweep(x,2,colSums(x),"/")
  H = - colSums(ifelse(freqs>0,freqs* log2(freqs),0))
  return(H)
}

#' warpper function for Startrac analysis
#' @importFrom data.table dcast
#' @importFrom plyr ldply adply llply
#' @importFrom parallel makeCluster stopCluster
#' @importFrom doParallel registerDoParallel
#' @importFrom methods new slot
#' @importFrom methods slot<-
#' @param cell.data data.frame. Each line for a cell, and these columns as required: `Cell_Name`, `clone.id`, `patient`, `majorCluster`, `loc`
#' @param proj character. String used to annotate the project.
#' @param cores integer. number of core to be used. default: NULL.
#' @param n.perm integer. number of permutation will be performed. If NULL, no permutation. (default: NULL)
#' @param verbose logical. wheter return intermediate result (some Startrac objects) 
#' @details run the Startrac pipeline
#' @return an list contains data.frame elements "cluster.data","pIndex.migr" and "pIndex.tran"
#' @export
#' @examples 
#' library("Startrac")
#' dat.file <- system.file("extdata/example.cloneDat.Zhang2018.txt",package = "Startrac")
#' in.dat <- read.table(dat.file,stringsAsFactors = FALSE,head=TRUE)
#' out <- Startrac.run(in.dat, proj="CRC", cores=2,verbose=FALSE)
#' 
Startrac.run <- function(cell.data, proj="CRC", cores=NULL,n.perm=NULL,verbose=F)
{
  ##tic("obj.proj")
  loginfo("initialize Startrac ...")
  obj.proj <- new("Startrac",cell.data,aid=proj,n.perm=n.perm,cores=cores)
  loginfo("calculate startrac index ...")
  obj.proj <- calIndex(obj.proj,cores=cores,n.perm=n.perm)
  loginfo("calculate pairwise index ...")
  obj.proj <- pIndex(obj.proj,cores=cores,n.perm=n.perm)
  if(!is.null(n.perm)){ 
    loginfo("get the significance")
    obj.proj <- getSig(obj.proj,obj.proj@cell.perm.data) 
  }else{
    obj.proj <- getSig(obj.proj,NULL) 
  }
  ##toc()
  
  obj.list <- NULL
  if(length(obj.proj@patient.size)>1)
  {
    loginfo("calculate indices of each patient ...")
    patient.vec <- names(obj.proj@patient.size[obj.proj@patient.size > 30])
    #cl <- makeCluster(if(is.null(cores)) (detectCores()-2) else cores)
    #registerDoParallel(cl)
    withCallingHandlers({
      obj.list <- llply(patient.vec,function(pid,cell.data){
        require("Startrac")
        obj <- new("Startrac",subset(cell.data,patient==pid),aid=pid)
        obj <- calIndex(obj)
        obj <- pIndex(obj,cores=1)
        obj <- getSig(obj,NULL)
        obj
      },cell.data=cell.data,.progress = "none",.parallel=F)
    },warning=function(w) {
      if(grepl("... may be used in an incorrect context:",conditionMessage(w)))
        ### strange bug, see https://github.com/hadley/plyr/issues/203
        invokeRestart("muffleWarning")
    })
    #stopCluster(cl)
  }
  loginfo("collect result")
  ret <- new("StartracOut",proj=proj)
  ## cluster index
  ret.slot.names <- c("cluster.data","pIndex.migr","pIndex.tran",
                      "cluster.sig.data","pIndex.sig.migr","pIndex.sig.tran")
#  if(!is.null(n.perm)){ 
#    ret.slot.names <- c(ret.slot.names,
#                        c("cluster.sig.data","pIndex.sig.migr","pIndex.sig.tran")) 
#  }
  for(v in ret.slot.names)
  {
    slot(ret, v) <- slot(obj.proj,v)
    if(!is.null(obj.list)){
      slot(ret, v) <- rbind(slot(ret, v),ldply(obj.list,function(obj){
        slot(obj,v)
      }))
    }
  }
  if(verbose){
    ret@objects <- c(obj.proj,obj.list)
  }
  loginfo("return")
  return(ret)
}

#' calculate Startrac.dist (tissue distribution preference)
#' @import data.table
#' @importFrom plyr aaply
#' @importFrom stats chisq.test
#' @param dat.tb data.frame. Each line for a cell, and these columns as required: `majorCluster`, `loc`
#' @param byPatient logical. whether calculate the index for each patient. (default: FALSE)
#' @param colname.cluster character. which column specify the cluster (default: "majorCluster")
#' @param colname.patient character. which column specify the patient  (default: "patient")
#' @param colname.tissue character. which column specify the tissue  (default: "loc")
#' @details calculate Startrac.dist (tissue distribution preference) which is based on Chisquare test.
#' @return an array full of R_{o/e}
#' @export
calTissueDist <- function(dat.tb,byPatient=F,colname.cluster="majorCluster",
							  colname.patient="patient",colname.tissue="loc")
{
	if(byPatient==F){
		N.o <- table(dat.tb[[colname.cluster]],dat.tb[[colname.tissue]])
		res.chisq <- chisq.test(N.o)
		R.oe <- (res.chisq$observed)/(res.chisq$expected)
	}else{
		N.o.byPatient <- table(dat.tb[[colname.patient]],
							   dat.tb[[cluster.colname]], dat.tb[[colname.tissue]])
		R.oe <- aaply(N.o.byPatient,1,function(x){
						 res.chisq <- chisq.test(x)
						 return((res.chisq$observed)/(res.chisq$expected))
							  })
	}
	return(R.oe)
}
