#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

NOISY_AUDIO_DIR="experiments/data/mix"
CLEAN_AUDIO_DIR="experiments/data/clean"
ENROLLMENT_DIR="experiments/data/clean"
EMBEDDING_NNET_DIR="voxceleb_trained"
DATA_DIR="data/train_orig" # [TODO]
FEATURES_DIR=$DATA_DIR/noisy_embedding

stage=2

set -euo pipefail

# mkdir -p $OUTPUT_DIR

mkdir -p $FEATURES_DIR

#abc=`feat-to-dim scp:./data/train_orig/noisy/feats.scp -`
#abc=`copy-feats scp:./data/train_orig/noisy/feats.scp ark,t:test_noisy`
#abc=`copy-vector scp:./voxceleb_trained/xvectors/xvector.scp ark,t:test`
#abc=`append-vector-to-feats scp:./data/train_orig/noisy/feats.scp scp:./voxceleb_trained/xvectors/xvector.scp ark,t:test_append`
#echo $abc
#stage=100500

# Data preparation
if [ $stage -le 2 ]; then
  local/prepare_data.sh $NOISY_AUDIO_DIR $CLEAN_AUDIO_DIR $ENROLLMENT_DIR \
    $DATA_DIR/noisy $DATA_DIR/clean $DATA_DIR/enrollment
fi
#stage=100500

# Embeddings preparation.
if [ $stage -le 3 ]; then
  steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj 2 --cmd "$train_cmd" \
    $DATA_DIR/enrollment 

  sid/compute_vad_decision.sh --nj 2 --cmd "$train_cmd" \
    $DATA_DIR/enrollment 

  sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj 2 \
    $EMBEDDING_NNET_DIR $DATA_DIR/enrollment \
    $EMBEDDING_NNET_DIR/xvectors
fi
#exit 1;
#stage=100500

# [TODO] Split into train/dev/eval

# Feature extraction,
# if [ $stage -le 4 ]; then
#   for dset in train dev eval; do
#     steps/make_mfcc.sh --nj 15 --cmd "$train_cmd" data/$mic/$dset
#     steps/compute_cmvn_stats.sh data/$mic/$dset
#     utils/fix_data_dir.sh data/$mic/$dset
#   done
# fi

# Feature extraction.
if [ $stage -le 4 ]; then
  # For noisy audio.
  steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/noisy
  # For clean audio.
  steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/clean

  for f in spk2utt utt2spk; do
    cp $DATA_DIR/noisy/$f $FEATURES_DIR/$f || exit 1;
  done
  # Append (with repetitions) embedding vectors to noisy features in order to use both of them in nnet3 config.
  append-vector-to-feats scp:$DATA_DIR/noisy/feats.scp scp:$EMBEDDING_NNET_DIR/xvectors/xvector.scp ark,scp:$FEATURES_DIR/feats.ark,$FEATURES_DIR/feats.scp || exit 1

fi

# Train nnet
if [ $stage -le 5 ]; then
  local/train_voice_filter.sh $FEATURES_DIR $DATA_DIR/clean/feats.scp "temp" --cmd "$train_cmd"
fi