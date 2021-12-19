#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh


# You may set 'mic' to:
#  ihm [individual headset mic- the default which gives best results]
#  sdm1 [single distant microphone- the current script allows you only to select
#        the 1st of 8 microphones]
#  mdm8 [multiple distant microphones-- currently we only support averaging over
#       the 8 source microphones].
# ... by calling this script as, for example,
# ./run.sh --mic sdm1
# ./run.sh --mic mdm8
mic=ihm

# Train systems,
nj=30 # number of parallel jobs,
stage=15
DO_PCA=false
#true
. utils/parse_options.sh

base_mic=$(echo $mic | sed 's/[0-9]//g') # sdm, ihm or mdm
nmics=$(echo $mic | sed 's/[a-z]//g') # e.g. 8 for mdm8.

set -euo pipefail

# Path where AMI gets downloaded (or where locally available):
AMI_DIR=$PWD/wav_db # Default,
case $(hostname -d) in
  fit.vutbr.cz) AMI_DIR=/mnt/matylda5/iveselyk/KALDI_AMI_WAV ;; # BUT,
  clsp.jhu.edu) AMI_DIR=/export/corpora4/ami/amicorpus ;; # JHU,
  cstr.ed.ac.uk) AMI_DIR= ;; # Edinburgh,
esac

[ ! -r data/local/lm/final_lm ] && echo "Please, run 'run_prepare_shared.sh' first!" && exit 1
final_lm=`cat data/local/lm/final_lm`
LM=$final_lm.pr1-7

# Download AMI corpus, You need around 130GB of free space to get whole data ihm+mdm,
if [ $stage -le 0 ]; then
  if [ -d $AMI_DIR ] && ! touch $AMI_DIR/.foo 2>/dev/null; then
    echo "$0: directory $AMI_DIR seems to exist and not be owned by you."
    echo " ... Assuming the data does not need to be downloaded.  Please use --stage 1 or more."
    exit 1
  fi
  if [ -e data/local/downloads/wget_$mic.sh ]; then
    echo "data/local/downloads/wget_$mic.sh already exists, better quit than re-download... (use --stage N)"
    exit 1
  fi
  local/ami_download.sh $mic $AMI_DIR
fi


if [ "$base_mic" == "mdm" ]; then
  PROCESSED_AMI_DIR=$AMI_DIR/beamformed
  if [ $stage -le 1 ]; then
    # for MDM data, do beamforming
    ! hash BeamformIt && echo "Missing BeamformIt, run 'cd ../../../tools/; extras/install_beamformit.sh; cd -;'" && exit 1
    local/ami_beamform.sh --cmd "$train_cmd" --nj 20 $nmics $AMI_DIR $PROCESSED_AMI_DIR
  fi
else
  PROCESSED_AMI_DIR=$AMI_DIR
fi

# Prepare original data directories data/ihm/train_orig, etc.
if [ $stage -le 2 ]; then
  local/ami_${base_mic}_data_prep.sh $PROCESSED_AMI_DIR $mic
  local/ami_${base_mic}_scoring_data_prep.sh $PROCESSED_AMI_DIR $mic dev
  local/ami_${base_mic}_scoring_data_prep.sh $PROCESSED_AMI_DIR $mic eval
fi

if [ $stage -le 3 ]; then
  for dset in train dev eval; do
    # this splits up the speakers (which for sdm and mdm just correspond
    # to recordings) into 30-second chunks.  It's like a very brain-dead form
    # of diarization; we can later replace it with 'real' diarization.
    seconds_per_spk_max=30
    [ "$mic" == "ihm" ] && seconds_per_spk_max=120  # speaker info for ihm is real,
                                                    # so organize into much bigger chunks.

    # Note: the 30 on the next line should have been $seconds_per_spk_max
    # (thanks: Pavel Denisov.  This is a bug but before fixing it we'd have to
    # test the WER impact.  I suspect it will be quite small and maybe hard to
    # measure consistently.
    utils/data/modify_speaker_info.sh --seconds-per-spk-max 30 \
      data/$mic/${dset}_orig data/$mic/$dset
  done
fi

# Feature extraction,
if [ $stage -le 4 ]; then
  for dset in train dev eval; do
    steps/make_mfcc.sh --nj 15 --cmd "$train_cmd" data/$mic/$dset
    steps/compute_cmvn_stats.sh data/$mic/$dset
    utils/fix_data_dir.sh data/$mic/$dset
  done
fi

# monophone training
if [ $stage -le 5 ]; then
  # Full set 77h, reduced set 10.8h,
  utils/subset_data_dir.sh data/$mic/train 15000 data/$mic/train_15k

  steps/train_mono.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train_15k data/lang exp/$mic/mono
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train data/lang exp/$mic/mono exp/$mic/mono_ali
fi

# context-dep. training with delta features.
if [ $stage -le 6 ]; then
  steps/train_deltas.sh --cmd "$train_cmd" \
    5000 80000 data/$mic/train data/lang exp/$mic/mono_ali exp/$mic/tri1
  steps/align_si.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train data/lang exp/$mic/tri1 exp/$mic/tri1_ali
fi

if [ $stage -le 7 ]; then
  # LDA_MLLT
  steps/train_lda_mllt.sh --cmd "$train_cmd" \
    --splice-opts "--left-context=3 --right-context=3" \
    5000 80000 data/$mic/train data/lang exp/$mic/tri1_ali exp/$mic/tri2
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train data/lang exp/$mic/tri2 exp/$mic/tri2_ali
  # Decode
   graph_dir=exp/$mic/tri2/graph_${LM}
  $decode_cmd --mem 4G $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_${LM} exp/$mic/tri2 $graph_dir
  steps/decode.sh --nj $nj --cmd "$decode_cmd" --config conf/decode.conf \
    $graph_dir data/$mic/dev exp/$mic/tri2/decode_dev_${LM}
  steps/decode.sh --nj $nj --cmd "$decode_cmd" --config conf/decode.conf \
    $graph_dir data/$mic/eval exp/$mic/tri2/decode_eval_${LM}
fi


if [ $stage -le 8 ]; then
  # LDA+MLLT+SAT
  steps/train_sat.sh --cmd "$train_cmd" \
    5000 80000 data/$mic/train data/lang exp/$mic/tri2_ali exp/$mic/tri3
  steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
    data/$mic/train data/lang exp/$mic/tri3 exp/$mic/tri3_ali
fi

if [ $stage -le 9 ]; then
  # Decode the fMLLR system.
  graph_dir=exp/$mic/tri3/graph_${LM}
  $decode_cmd --mem 4G $graph_dir/mkgraph.log \
    utils/mkgraph.sh data/lang_${LM} exp/$mic/tri3 $graph_dir
  steps/decode_fmllr.sh --nj $nj --cmd "$decode_cmd" --config conf/decode.conf \
    $graph_dir data/$mic/dev exp/$mic/tri3/decode_dev_${LM}
  steps/decode_fmllr.sh --nj $nj --cmd "$decode_cmd" --config conf/decode.conf \
    $graph_dir data/$mic/eval exp/$mic/tri3/decode_eval_${LM}
fi

if [ $stage -le 10 ]; then
  # The following script cleans the data and produces cleaned data
  # in data/$mic/train_cleaned, and a corresponding system
  # in exp/$mic/tri3_cleaned.  It also decodes.
  #
  # Note: local/run_cleanup_segmentation.sh defaults to using 50 jobs,
  # you can reduce it using the --nj option if you want.
  local/run_cleanup_segmentation.sh --mic $mic
fi

if [ $stage -le 11 ]; then
  ali_opt=
  [ "$mic" != "ihm" ] && ali_opt="--use-ihm-ali true"
  local/chain/run_tdnn.sh $ali_opt --mic $mic
fi

#if [ $stage -le 12 ]; then
#  the following shows how you would run the nnet3 system; we comment it out
#  because it's not as good as the chain system.
#  ali_opt=
#  [ "$mic" != "ihm" ] && ali_opt="--use-ihm-ali true"
# local/nnet3/run_tdnn.sh $ali_opt --mic $mic
#fi

if [ $stage -le 13 ]; then
  echo "Preraring enrollment data for dev and eval."
  temp_dir=data/temp
  mkdir -p $temp_dir
  enrollment_dir=../voicefilter/data/audio/clean
  for dset in dev "eval"; do
    mkdir -p data/$mic/enrollment/$dset
    #AMI_EN2002a_H00
    awk '{print $1}' data/$mic/$dset/feats.scp > $temp_dir/uttids
    awk '{print $1}' data/$mic/$dset/wav.scp | sort -u - > $temp_dir/spkids
    awk '{print $1}' $temp_dir/spkids | \
      perl -ne 'split; $_ =~ m/AMI_(.*)_H0([0-4])/; print "/$1/$2/enrollment/$1.enrollment-$2.wav\n"' | \
      awk -v folder=$enrollment_dir '{print folder $1}' - | \
      paste $temp_dir/spkids - > $temp_dir/"$dset"_enrollment_wav_temp.scp

    awk '{print $1" sox -c 1 -t wavpcm -e signed-integer "$2" -t wavpcm - |"}' $temp_dir/"$dset"_enrollment_wav_temp.scp > $temp_dir/"$dset"_enrollment_wav.scp
    awk '{print $1}' $temp_dir/uttids | \
      perl -ne 'split; $_ =~ m/AMI_(.*)_H0([0-4])_.*/; print "AMI_$1_H0$2\n"' | \
      paste $temp_dir/uttids - > data/$mic/enrollment/$dset/utt2spk_orig
    paste $temp_dir/spkids $temp_dir/spkids > data/$mic/enrollment/$dset/utt2spk
    utils/utt2spk_to_spk2utt.pl <data/$mic/enrollment/$dset/utt2spk >data/$mic/enrollment/$dset/spk2utt
    #for f in spk2utt utt2spk; do
    #  cp data/$mic/$dset/$f data/enrollment/$dset/$f
    #done
    #paste $temp_dir/spkids $temp_dir/spkids > data/enrollment/$dset/spk2utt
    #cp data/enrollment/$dset/spk2utt data/enrollment/$dset/utt2spk
    cp $temp_dir/"$dset"_enrollment_wav.scp data/$mic/enrollment/$dset/wav.scp
  done
  echo "Finished data preparation for enrollment"
fi
#stage=100500

if [ $stage -le 14 ]; then
  echo "Embedding preparation for dev eval."
  mkdir -p data/xvectors
  #emb_cmd=run.pl
  for dset in dev eval; do
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config ../voicefilter/conf/xvectors/mfcc.conf \
      --pitch-config ../voicefilter/conf/xvectors/pitch.conf --nj 10 --cmd "$train_cmd" \
      data/$mic/enrollment/$dset

    utils/fix_data_dir.sh data/$mic/enrollment/$dset

    ../voicefilter/sid/compute_vad_decision.sh --nj 10 --cmd "$train_cmd" \
      --vad-config ../voicefilter/conf/xvectors/vad.conf data/$mic/enrollment/$dset

    ../voicefilter/sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj 10 \
      ../voicefilter/voxceleb_trained data/$mic/enrollment/$dset data/$mic/xvectors/"$dset"_orig
  done
fi
XVECTORS_DIR_SUFFIX="_orig"
if  $DO_PCA; then
  XVECTORS_DIR_SUFFIX=""
fi

if [ $stage -le 15 ] && $DO_PCA; then
  for dset in dev eval; do
    est-pca --read-vectors=true --dim=128 scp:data/xvectors/"$dset"_orig/xvector.scp data/xvectors/"$dset"_orig/pca128.mat
    mkdir -p data/xvectors/$dset
    transform-vec data/xvectors/"$dset"_orig/pca128.mat scp:data/xvectors/"$dset"_orig/xvector.scp \
      ark,scp:data/xvectors/$dset/xvector.ark,data/xvectors/$dset/xvector.scp
  done
fi

#stage=100500
features_dir=data/$mic/with_embedding
if [ $stage -le 15 ]; then
  mkdir -p logs_vf
  #features_dir=data/with_embedding
  #for dset in dev "eval"; do
  for dset in dev eval; do
    # Create fbanks
    mkdir -p data/$mic/"$dset"_fbank
    for f in glm reco2file_and_channel segments spk2utt stm text utt2dur utt2num_frames utt2spk wav.scp; do
      cp data/$mic/$dset/$f data/$mic/"$dset"_fbank/$f
    done

    # We use --compress false since eventually we convert these fbanks to mfcc after applying VF model.
    steps/make_fbank.sh --fbank-config ../voicefilter/conf/fbank.conf --nj 8 --compress false --cmd "$train_cmd" data/$mic/"$dset"_fbank
    utils/fix_data_dir.sh data/$mic/"$dset"_fbank

    mkdir -p $features_dir/$dset
    append-xvectors scp:data/$mic/xvectors/$dset$XVECTORS_DIR_SUFFIX/xvector.scp ark:data/$mic/enrollment/$dset/utt2spk_orig \
      scp:data/$mic/"$dset"_fbank/feats.scp ark,scp:$features_dir/$dset/feats.ark,$features_dir/$dset/feats.scp
    #../voicefilter/local/append_noisy_and_xvectors.sh data/$mic/"$dset"_fbank data/xvectors/$dset$XVECTORS_DIR_SUFFIX \
    #  $features_dir/$dset logs_vf --cmd "$train_cmd"
    echo "appended"

    #mkdir -p "$dset"_vf
    cp -r data/$mic/"$dset"_fbank data/$mic/"$dset"_vf
  done
fi
#stage=100500

if [ $stage -le 16 ]; then
  for dset in dev eval; do
    for f in spk2utt utt2spk; do
      cp data/$mic/"$dset"_fbank/$f $features_dir/$dset/$f
    done
    utils/fix_data_dir.sh $features_dir/$dset
    output_dir=data/$mic/"$dset"_vf/exp_log_fbanks_340
    mkdir -p $output_dir
    ../voicefilter/local/evaluate.sh --iter final_340 --cmd "$decode_cmd" --nj 16 --use-gpu true \
      $features_dir/$dset ../voicefilter/exp_log_fbanks $output_dir || exit 1;
    echo "used vf model"
    cp $output_dir/output.scp $output_dir/feats_fbank.scp
    for f in glm reco2file_and_channel segments spk2utt stm text utt2dur utt2num_frames utt2spk wav.scp; do
      cp data/$mic/"$dset"_vf/$f $output_dir/$f
    done
    for f in segments text utt2dur utt2num_frames utt2spk; do
      awk '{print $1;}' data/with_embedding/$dset/feats.scp | join -1 1 -2 1 - $output_dir/$f > $output_dir/"$f"_temp
      cp $output_dir/"$f"_temp $output_dir/$f
      rm $output_dir/"$f"_temp
    done
    utils/utt2spk_to_spk2utt.pl <$output_dir/utt2spk >$output_dir/spk2utt || exit 1;
  done
fi
#stage=100500
#awk '{print $1;}' abc1 | join -1 1 -2 1 - abc2
if [ $stage -le 17 ]; then
  for dset in dev eval; do
    utils/fix_data_dir.sh data/$mic/"$dset"_vf/exp_log_fbanks_340
    # Here we convert fbank features attained after applying VF model to MFCC features
    # expected by ASR model.
    # Note: It's important to have the same number of jobs as when making original fbanks!
    ../voicefilter/local/fbank_to_mfcc.sh --mfcc-config conf/mfcc_hires80.conf --nj 8 \
      --cmd "$train_cmd" data/$mic/"$dset"_vf/exp_log_fbanks_340
  done
fi
#stage=100500

if [ $stage -le 18 ]; then
#  cp -r data/$mic/train_cleaned data/$mic/train_cleaned_vf

#  for dset in dev; do
  #for dset in dev "eval"; do
    #utils/fix_data_dir.sh data/$mic/"$dset"_vf
    #steps/make_mfcc.sh --nj 8 --mfcc-config conf/mfcc_hires80.conf \
    #  --cmd run.pl data/$mic/"$dset"_vf_hires
    #steps/compute_cmvn_stats.sh data/$mic/"$dset"_vf_hires
    #utils/fix_data_dir.sh data/$mic/"$dset"_vf_hires

#    ../voicefilter/local/append_noisy_and_xvectors.sh data/$mic/"$dset"_hires data/xvectors/$dset \
#      $features_dir/$dset logs_vf --cmd "$train_cmd"
#    echo "appended"

#    utils/fix_data_dir.sh $features_dir/$dset

#    ../voicefilter/local/evaluate.sh $features_dir/$dset ../voicefilter/exp data/$mic/"$dset"_vf \
#      --cmd "$decode_cmd" --nj 16 --use-gpu yes || exit 1;
#    cp data/$mic/"$dset"_vf/output.scp data/$mic/"$dset"_vf/feats.scp

    #steps/online/nnet2/extract_ivectors_online.sh --cmd run.pl --nj 8 \
    #  data/$mic/"$dset"_vf_hires exp/$mic/nnet3_cleaned/extractor \
    #  exp/$mic/nnet3_cleaned/ivectors_"$dset"_vf_hires
#  done
  #for dset in dev "eval"; do
  for dset in dev eval; do
    #api_opt=
    #[ "$mic" != "ihm" ] && ali_opt="--use-ihm-ali true"
    utils/fix_data_dir.sh data/$mic/"$dset"_vf/exp_log_fbanks_340
    local/chain/evaluate_vf.sh data/$mic/"$dset"_vf/exp_log_fbanks_340 exp_log_fbanks_340 $dset --mic $mic
  done
fi

exit 0
