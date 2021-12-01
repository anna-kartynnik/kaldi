#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

MUSAN_ROOT="musan_corpora"
AMI_AUDIO_DIR="experiments/amicorpus"
AMI_ANNOTATIONS_DIR="experiments/annotations"
NOISY_AUDIO_DIR="data/audio/mix"
CLEAN_AUDIO_DIR="data/audio/clean"
#"experiments/data/clean"
#"data/processed/clean"
ENROLLMENT_DIR="data/audio/clean"
EMBEDDING_NNET_DIR="voxceleb_trained"
PREPARED_DATA_DIR="data/prepared2"
DATA_DIR="data/processed2"
FEATURES_DIR=$DATA_DIR/noisy_embedding
LOGS_DIR="logs"
VF_NNET_DIR="exp2"
# Chunk length for voice filter (in seconds)
CHUNK_LENGTH=3

stage=0

set -euo pipefail

# mkdir -p $OUTPUT_DIR

mkdir -p $FEATURES_DIR

#abc=`feat-to-dim scp:./data/train_orig/noisy/feats.scp -`
#abc=`copy-feats scp:./$DATA_DIR/clean/train1/feats.scp ark,t:train_clean`
#abc=`copy-feats scp:./$VF_NNET_DIR/output/output.scp ark,t:exp3_output`
#abc=`copy-vector scp:./voxceleb_trained/xvectors/xvector.scp ark,t:test`
#abc=`append-vector-to-feats scp:./data/train_orig/noisy/feats.scp scp:./voxceleb_trained/xvectors/xvector.scp ark,t:test_append`
#echo $abc
#stage=100500

if [ $stage -le 0 ]; then
  # Prepare the MUSAN corpus, which consists of music, speech, and noise
  # suitable for augmentation.
  if [ ! -d "$MUSAN_ROOT" ]; then
    echo "Downloading MUSAN corpora"
    mkdir -p $MUSAN_ROOT
    wget -c -nv -P $MUSAN_ROOT https://us.openslr.org/resources/17/musan.tar.gz
    tar -xf $MUSAN_ROOT/musan.tar.gz -C $MUSAN_ROOT
  else
    echo "$MUSAN_ROOT folder exists, skipping the stage of downloading MUSAN corpora"
  fi
fi
#stage=100500

# Data extraction (extract clean/enrollment/mixed audio using transcripts)
if [ $stage -le 1 ]; then
  python3 local/clean_audio_extractor.py --audio-folder $AMI_AUDIO_DIR --annotations-folder $AMI_ANNOTATIONS_DIR \
    --output-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/extraction --offset 100 --enrollment-duration-threshold 2000 \
    --chunk-length $CHUNK_LENGTH --combine --num-jobs 8
  python3 local/split_mix_audio.py --clean-audio-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/mix \
    --mix-folder $NOISY_AUDIO_DIR --chunk-length $CHUNK_LENGTH --add-other-noise \
    --musan-folder $MUSAN_ROOT/musan --num-jobs 8
fi
#stage=100500

# Data preparation (preparing for feature extraction)
if [ $stage -le 2 ]; then
  local/prepare_data.sh $NOISY_AUDIO_DIR $CLEAN_AUDIO_DIR $ENROLLMENT_DIR \
    $PREPARED_DATA_DIR/noisy $PREPARED_DATA_DIR/clean $PREPARED_DATA_DIR/enrollment
fi
#stage=100500

# Data splitting to train/test datasets.
if [ $stage -le 3 ]; then
  # Combine dev and eval meetings to use them as a test set.
  cat local/split_dev.orig local/split_eval.orig | sort -u > local/split_test.orig
  # Here the data will be splitted into train/test sets.
  for audio_type in noisy clean enrollment; do
    local/split_data.sh $PREPARED_DATA_DIR/$audio_type $DATA_DIR/$audio_type local
  done
fi
#stage=100500

# Embeddings preparation.
if [ $stage -le 4 ]; then
  for dset in train test; do
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/xvectors/mfcc.conf \
      --pitch-config conf/xvectors/pitch.conf --nj 2 --cmd "$train_cmd" $DATA_DIR/enrollment/$dset

    sid/compute_vad_decision.sh --nj 2 --cmd "$train_cmd" --vad-config conf/xvectors/vad.conf \
      $DATA_DIR/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj 2 \
      $EMBEDDING_NNET_DIR $DATA_DIR/enrollment/$dset \
      $DATA_DIR/xvectors/$dset
  done
fi
#stage=100500

# Feature extraction.
if [ $stage -le 5 ]; then
  for dset in train test; do
    for audio_type in noisy clean; do
      #steps/make_fbank.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;
      steps/make_mfcc.sh --nj 2 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;
      steps/compute_cmvn_stats.sh $DATA_DIR/$audio_type/$dset
      utils/fix_data_dir.sh $DATA_DIR/$audio_type/$dset
    done

    mkdir -p $FEATURES_DIR/$dset || exit 1;
    local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset $DATA_DIR/xvectors/$dset $FEATURES_DIR/$dset \
      $LOGS_DIR --cmd "$train_cmd"

  done
fi
#stage=100500

# Train nnet
if [ $stage -le 6 ]; then
  local/train_voice_filter.sh $FEATURES_DIR/train $DATA_DIR/clean/train/feats.scp $VF_NNET_DIR --cmd "$train_cmd"
fi
stage=100500

# Evaluate
if [ $stage -le 7 ]; then
  #local/evaluate.sh $FEATURES_DIR/test $VF_NNET_DIR $VF_NNET_DIR/output --cmd "$decode_cmd" --nj 2 || exit 1;
  local/evaluate.sh $FEATURES_DIR/train $VF_NNET_DIR $VF_NNET_DIR/output --cmd "$decode_cmd" --nj 2 || exit 1;
fi

# Evaluate
# if [ $stage -le 8 ]; then
#   wav-copy ark:exp2/output/output.1.ark:23 exp2/output/AMI_ES2002a_H0001_3012.wav
# fi