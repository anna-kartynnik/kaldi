#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

AMI_AUDIO_DIR="experiments/amicorpus"
AMI_ANNOTATIONS_DIR="experiments/annotations"
NOISY_AUDIO_DIR="data/processed/mix"
CLEAN_AUDIO_DIR="data/processed/clean"
#"experiments/data/clean"
#"data/processed/clean"
ENROLLMENT_DIR="data/processed/clean"
EMBEDDING_NNET_DIR="voxceleb_trained"
DATA_DIR="data/processed/train_orig" # [TODO]
FEATURES_DIR=$DATA_DIR/noisy_embedding
LOGS_DIR="logs"
# Chunk length for voice filter in seconds
CHUNK_LENGTH=3

stage=1

set -euo pipefail

# mkdir -p $OUTPUT_DIR

mkdir -p $FEATURES_DIR

#abc=`feat-to-dim scp:./data/train_orig/noisy/feats.scp -`
#abc=`copy-feats scp:./data/train_orig/noisy/feats.scp ark,t:test_noisy`
#abc=`copy-vector scp:./voxceleb_trained/xvectors/xvector.scp ark,t:test`
#abc=`append-vector-to-feats scp:./data/train_orig/noisy/feats.scp scp:./voxceleb_trained/xvectors/xvector.scp ark,t:test_append`
#echo $abc
#stage=100500

# Data extraction (extract clean/enrollment/mixed audio using transcripts)
if [ $stage -le 1 ]; then
  python3 local/clean_audio_extractor.py --audio-folder $AMI_AUDIO_DIR --annotations-folder $AMI_ANNOTATIONS_DIR \
    --output-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/extraction --offset 100 --enrollment-duration-threshold 2000 \
    --chunk-length $CHUNK_LENGTH --combine --num-jobs 8
  python3 local/split_mix_audio.py --clean-audio-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/mix \
    --mix-folder $NOISY_AUDIO_DIR --chunk-length $CHUNK_LENGTH --num-jobs 8
fi

# Data preparation (preparing for feature extraction)
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