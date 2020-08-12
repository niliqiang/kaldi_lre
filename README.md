# kaldi_lre  
## 1. Introduction  
My language recognition system based on Kaldi, using CommonVoice dataset.  
kaldi_lre 是根据 lre07, sre08, sre10, sre16 修改而来，使用的是 CommonVoice 数据集。 
kaldi_lre v1 版本是利用 GMM-UBM, iVectors 以及 logistic regression/CDS/LDA+CDS/LDA+PLDA 实现的语种识别系统。

## 2. Deploy
**step1:** 安装kaldi  
**step2:** git clone本仓库到kaldi/egs目录下  
**step3:** 修改run.sh脚本中数据集路径  
**step4:** 运行run.sh  
