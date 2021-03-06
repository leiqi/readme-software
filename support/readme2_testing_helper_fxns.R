
f2n <- function(.){as.numeric(as.character(.))}

library2 <- function(lib_name, loadin = T){ 
  eval_value <- try(class(lib_name), T)
  if( eval_value != "character" | class(eval_value) == "try-error" ){ lib_name <- deparse(substitute(lib_name)) } 
  if( !lib_name %in% rownames(installed.packages()) ){
    LIB_counter <- 0; LIB_ok <- F 
    while(LIB_ok == F){ 
      LIB_counter <- LIB_counter + 1 
      print(sprintf("Trying %s for %s", .libPaths()[LIB_counter], lib_name))
      try(eval(parse(text = sprintf("install.packages('%s', 
                                    repos = 'http://cran.us.r-project.org',
                                    lib = .libPaths()[LIB_counter] )", lib_name))), T)
      LIB_ok <- lib_name %in% rownames(installed.packages())
      if(LIB_counter > length(.libPaths())){LIB_ok <- T}
    }
  }
  if(loadin == T){ 
    eval(parse(text = sprintf("require('%s', quietly = T)", lib_name)))
  } 
}

rdirichlet <- function(n, alpha) {
  normalize <- function(.) . / sum(.)
  samps <- vapply(alpha, function(al) stats::rgamma(n, al, 1), numeric(n))
  if(class(samps) == "matrix" ){ ret_q <- t(apply(samps, 1, normalize)) }
  if(class(samps) == "numeric" ){ ret_q <- normalize(samps) }
  return( ret_q ) 
}
liblinearModelFunction<-function(xTrain){
  library2("LiblineaR", loadin = F)
  LiblineaR::LiblineaR(data=xTrain[,-1],target=xTrain[,1], type=7,cost=1, bias=TRUE)
}
liblinearPredFunction<-function(PLT, testData){
  probs<-predict(PLT,testData, proba=T)$probabilities
  return(  probs ) 
}
naiveMethod<-function(trainMatrix,testMatrix,baseClassifierModelFunction=liblinearModelFunction,baseClassifierPredFunction=liblinearPredFunction){
  model<-baseClassifierModelFunction(trainMatrix)
  probs<-baseClassifierPredFunction(model,testMatrix)
}
EnsembleMethod <- function(train_cats, train_feat, test_feat, labeled_pd){ 
  library2("randomForest", loadin = F)
  library2("e1071", loadin = F)
  
  KeepCols <- apply(test_feat, 2, sd) > 0 & apply(train_feat, 2, sd) > 0 
  train_feat <- train_feat[,KeepCols]
  test_feat <- test_feat[,KeepCols]
  
  DF1 <- as.data.frame(  cbind( train_cats, train_feat) )    
  DF1[,-1] <- apply(DF1[,-1] , 2, f2n); colnames(DF1)[1] <- "TRUTH"
  
  Regression_method <-  naiveMethod(DF1, test_feat)
  Regression_est <- try(colMeans(  naiveMethod(DF1, test_feat) ) , T)  
  Regression_est_count <- try( apply(naiveMethod(DF1, test_feat), 
                                     1, function(zeta){ sample(names(zeta)[zeta==max(zeta)], 1) }), T)
  Regression_est_count <- table( Regression_est_count ) / sum(table(Regression_est_count))
  
  Forest_method <- try(randomForest::randomForest(x = DF1[,-1], y = as.factor(DF1[,1]) ), T)  
  Forest_est <- try(colMeans( predict(Forest_method  , test_feat , type = "prob"), na.rm = T  ) , T)  
  Forest_est_count <- try(predict(Forest_method  , test_feat , type = "class") , T)
  Forest_est_count <- try(table(Forest_est_count)/sum(table(Forest_est_count)))
  
  SVM_method <-  try(e1071::svm(x = DF1[,-1], y = as.factor(DF1[,1]), probability = T ), T)  
  SVM_est <- try(colMeans( attr(predict(SVM_method , test_feat , probability = T) , "probabilities" ), na.rm = T )  , T)  
  SVM_est_count <- try(predict(SVM_method , test_feat , probability = F), T) 
  SVM_est_count <- try(table(SVM_est_count)/sum(table(SVM_est_count)))
  
  NaiveBayes_method <- try(e1071::naiveBayes(x = DF1[,-1], y = as.factor(DF1[,1]), laplace = 1), T)  
  NaiveBayes_est <- try(colMeans(predict(NaiveBayes_method, test_feat, type = "raw", laplace = 0.5) ), T)  
  NaiveBayes_est_count <- try(predict(NaiveBayes_method, test_feat, type = "class", laplace = 0.5), T)  
  NaiveBayes_est_count <- try(table(NaiveBayes_est_count)/sum(table(NaiveBayes_est_count)))
  
  method_names <- c("Regression", "Forest", "SVM", "NaiveBayes")
  for(method_name in method_names){ 
    eval(parse(text = sprintf("%s_est <- %s_est[names(labeled_pd)]; %s_est[is.na(%s_est)] <- 0; %s_est <- f2n(%s_est); 
                              names(%s_est) <- names(labeled_pd)", 
                              method_name, method_name, method_name, method_name, method_name, method_name, method_name) ))
    eval(parse(text = sprintf("if(all(%s_est==0)){%s_est[] <- NA}", method_name, method_name) ))
    eval(parse(text = sprintf("%s_est_count <- %s_est_count[names(labeled_pd)]; %s_est_count[is.na(%s_est_count)] <- 0 ;
                              %s_est_count <- f2n(%s_est_count); names(%s_est_count) <- names(labeled_pd)", 
                              method_name, method_name, method_name, method_name, method_name, method_name, method_name) ))
    eval(parse(text = sprintf("if(all(%s_est_count==0)){%s_est_count[] <- NA}", method_name, method_name) ))
  }
  
  EstMat <- rbind(Regression_est, Forest_est, SVM_est, NaiveBayes_est)
  EstMat <- apply(EstMat, 2, f2n)
  est_final <- colMeans(EstMat, na.rm = T) 
  
  EstMat_count <- rbind(Regression_est_count, Forest_est_count, SVM_est_count, NaiveBayes_est_count)
  EstMat_count <- apply(EstMat_count, 2, f2n)
  est_final_count <- colMeans(EstMat_count, na.rm = T) 
  
  final_list <- list(ensemble = est_final, 
                     NaiveBayes_est = NaiveBayes_est,
                     SVM_est = SVM_est, Forest_est = Forest_est, Regression_est = Regression_est)
  final_list_count <- list(ensemble_count = est_final_count, 
                           NaiveBayes_est_count = NaiveBayes_est_count,
                           SVM_est_count = SVM_est_count, 
                           Forest_est_count = Forest_est_count, Regression_est_count = Regression_est_count)
  return( list(final_list=final_list,
               final_list_count=final_list_count) )   
}
