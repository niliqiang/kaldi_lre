# kaldi_lre  
## 1. Introduction  
My language recognition system based on Kaldi, using CommonVoice dataset.  
kaldi_lre 是根据 lre07, sre08, sre10, sre16 修改而来，使用的是 CommonVoice 数据集  
kaldi_lre v1 版本是利用 GMM-UBM, iVectors 以及 logistic regression/CDS/LDA+CDS/LDA+PLDA 实现的语种识别系统。  
kaldi_lre v2 版本在v1的基础之上，使用了带瓶颈层的神经网络，但由于时间关系，并没有优化参数。  

## 2. Deploy
**step1:** 安装kaldi  
**step2:** git clone本仓库到kaldi/egs目录下  
**step3:** 修改run.sh脚本中数据集路径  
**step4:** 运行run.sh  

## 3. Others
此工程是语种识别系统的语种识别算法实现  
语种识别系统的server端实现见：[lre_server](https://github.com/niliqiang/lre_server)  
语种识别系统的client端实现由于可能涉及到商业秘密，暂不开源，如需要参考请单独联系  
基于此语种识别系统完成的硕士毕业论文：[倪立强. 基于i-vector的语种识别系统设计与实现[D].北京邮电大学,2021.](https://kns.cnki.net/kcms/detail/detail.aspx?dbcode=CMFD&dbname=CMFD202201&filename=1021130386.nh&uniplatform=NZKPT&v=Oxe1lP-f9RxxsTkUI8AR0V4ktJenmmobzK4lmEXds_M3LM8hpOrMBLWa2R_zkNGe)  
