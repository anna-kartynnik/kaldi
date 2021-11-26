#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

AMI_AUDIO_DIR="experiments/amicorpus"
AMI_ANNOTATIONS_DIR="experiments/annotations"
NOISY_AUDIO_DIR="data/audio/mix"
CLEAN_AUDIO_DIR="data/audio/clean"
#"experiments/data/clean"
#"data/processed/clean"
ENROLLMENT_DIR="data/audio/clean"
EMBEDDING_NNET_DIR="voxceleb_trained"
PREPARED_DATA_DIR="data/prepared"
DATA_DIR="data/processed"
FEATURES_DIR=$DATA_DIR/noisy_embedding
LOGS_DIR="logs"
VF_NNET_DIR=exp
# Chunk length for voice filter (in seconds)
CHUNK_LENGTH=3

stage=4

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
    $PREPARED_DATA_DIR/noisy $PREPARED_DATA_DIR/clean $PREPARED_DATA_DIR/enrollment
  # Combine dev and eval meetings to use them as a test set.
  # [TODO] remove abc!!!!!
  cat local/split_dev.orig local/split_eval.orig local/split_abc.orig | sort -u > local/split_test.orig
  # Here the data will be splitted into train/test sets.
  for audio_type in noisy clean enrollment; do
    local/split_data.sh $PREPARED_DATA_DIR/$audio_type $DATA_DIR/$audio_type local
  done
fi
#stage=100500

# Embeddings preparation.
if [ $stage -le 3 ]; then
  for dset in train test; do
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/mfcc.conf --nj 2 \
      --cmd "$train_cmd" $DATA_DIR/enrollment/$dset

    sid/compute_vad_decision.sh --nj 2 --cmd "$train_cmd" \
      $DATA_DIR/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj 2 \
      $EMBEDDING_NNET_DIR $DATA_DIR/enrollment/$dset \
      $DATA_DIR/xvectors/$dset
  done
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
  for dset in train test; do
    for audio_type in noisy clean; do
      steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;
    done
    # # For noisy audio.
    # steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/noisy
    # # For clean audio.
    # steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/clean

    mkdir -p $FEATURES_DIR/$dset || exit 1;
    local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset $DATA_DIR/xvectors/$dset $FEATURES_DIR/$dset \
      $LOGS_DIR --cmd "$train_cmd"

    # for f in spk2utt utt2spk; do
    #   cp $DATA_DIR/noisy/$f $FEATURES_DIR/$f || exit 1;
    # done
    # # Append (with repetitions) embedding vectors to noisy features in order to use both of them in nnet3 config.
    # append-vector-to-feats scp:$DATA_DIR/noisy/feats.scp scp:$EMBEDDING_NNET_DIR/xvectors/xvector.scp ark,scp:$FEATURES_DIR/feats.ark,$FEATURES_DIR/feats.scp || exit 1
  done
fi

# Train nnet
if [ $stage -le 5 ]; then
  local/train_voice_filter.sh $FEATURES_DIR/train $DATA_DIR/clean/train/feats.scp $VF_NNET_DIR --cmd "$train_cmd"
fi