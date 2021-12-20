1. UNI and Full Name: Hanna Kartynnik (hk3129@columbia.edu)
2. Date: 2021-12-19
3. Project Title: Automated speech recognition in the multi-speaker environment with a VoiceFilter model
4. Project summary:
   We attempt to suppress noise and other speakers on the acoustic feature level in a multi-speaker environment
   given a reference clean audio recording of the target speaker, inspired by the VoiceFilter and VoiceFilter Lite papers.
5. Required tools: The AMI recipe requires SRILM (kaldi/tools/extras/install_srilm.sh) that has been installed in my copy.
6. Main scripts:
   Prerequisite: activate the Python virtual environment in ~hk3129/virtualenv using the command . ~hk3129/virtualenv/bin/activate
   (alternatively, install the dependencies from kaldi/egs/ami/voicefilter/local/requirements.txt via pip).           

   The demo decoding on a small subsample of the development set (19 utterances of 1 speaker) is available via running the command
   ./run_decoding.sh with no arguments from the kaldi/egs/ami/voicefilter directory.
   It is expected that the script finishes with the zero exit code indicating success and prints out the resulting WER to standard output.
   I got 11.7% for this single speaker (ami_es2011a_h01_fee042).

   ~hk3129/kaldi/egs/ami/s5b/exp/ihm/chain_cleaned/tdnn1j_sp_bi/decode_dev/ascore_10/exp_log_fbanks.ctm.filt.sys suggests that in the non-filtered pipeline it was 8.5%.

   The logs for the (GPU) decoding of the entire dev/eval sets are in ~hk3129/kaldi/egs/ami/s5b/exp/ihm/chain_cleaned/tdnn1j_sp_bi/decode_{dev,eval}_vf/.
   For this model, dev. WER is 21.2% and test WER is 26.0%.

   The training was performed with the run_vf.sh script in the same directory.

   The scripts rely on the pretrained VoxCeleb x-vector extractor in voicefilter/voxceleb_trained and
   the pretrained AMI model in s5b/exp/ihm/chain_cleaned/tdnn1j_sp_bi, as well as data in voicefilter/data.
   

The modified files are (relative to ~hk3129):
- kaldi/egs/ami/voicefilter/           (added)     The main recipe for training the filter. (Completely by me.)
- kaldi/egs/ami/s5b/                   (modified)  The modified baseline recipe that can run with the filter applied. (Minor modifications.)
- kaldi/src/featbin/fbank-to-mfcc.cc   (added)     A program for producing MFCC features based on (modified) mel or log-mel filter banks.
                                                   (Implemented from scratch by me.)
- kaldi/src/featbin/append-xvectors.cc (added)     A program for appending speaker embeddings to feature matrix rows.
                                                   (Taken from https://gist.github.com/Determinant/089076dd87fa820f57ea with insignificant changes.)
- kaldi/src/featbin/Makefile.kaldi     (moved)     The original GNU Make file for featbin/. Included in the new one.
- kaldi/src/featbin/Makefile           (recreated) The GNU Make file that includes the original one and adds rules to build the two C++ programs above.

WARNING: Whereas most of the files/folders in ~hk3129/kaldi are symbolic links to respective files/folders in ~kaldi/,
         some are symbolic links to my own Kaldi fork in ~hk3129/uni/kaldi. Please consider this when using Unix utilities for automation,
         since some of them don't follow symbolic links by default.
         The following command gives an approximate list of files authored or modified by me (it is the contents of filelist.txt):
           { find ~hk3129/kaldi/egs/ami/voicefilter/local/ -type f; find kaldi -xtype f -exec readlink -f {} +; } |
             egrep -v '/home/kaldi/|/kaldi/tools/|/exp|/data/|/wav_db/|\.o$|\.depend\.mk|/logs|\.orig$|/__pycache__|\.swp$' | sort
