#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh

mic=ihm
use_gpu=false
calculate_error=false

MUSAN_ROOT="musan_corpora"
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
VF_NNET_DIR="exp"
# Chunk length for voice filter (in seconds)
CHUNK_LENGTH=3
DO_PCA=false
PCA_DIM=256
DECODE_SETS="dev eval"


stage=6

set -euo pipefail

# mkdir -p $OUTPUT_DIR

mkdir -p $FEATURES_DIR


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

# Check that AMI audio and transcript files are downloaded.
if [ $stage -le 1 ]; then
  if [ ! -d $AMI_AUDIO_DIR ]; then
    echo "There is no audio data has been found. Please run stage 0 from ../s5b/run.sh"
    exit 1;
  fi
  if [ ! -d $AMI_ANNOTATIONS_DIR ]; then
    echo "There is no transcript data found. Please run ../s5b/run_prepare_shared.sh"
    exit 1;
  fi
fi

# Data extraction (extract clean/enrollment/mixed audio using transcripts)
if [ $stage -le 2 ]; then
  python3 local/clean_audio_extractor.py --audio-folder $AMI_AUDIO_DIR --annotations-folder $AMI_ANNOTATIONS_DIR \
    --output-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/extraction --offset 100 --enrollment-duration-threshold 3000 \
    --chunk-length $CHUNK_LENGTH --combine --num-jobs 4

  python3 local/split_mix_audio.py --clean-audio-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/mix \
    --mix-folder $NOISY_AUDIO_DIR --chunk-length $CHUNK_LENGTH --add-other-noise \
    --musan-folder $MUSAN_ROOT/musan --num-jobs 4 --no-split-musan
fi
#stage=100500

# Data preparation (preparing for feature extraction) and splitting into train/dev/eval.
if [ $stage -le 3 ]; then
  local/prepare_data.sh $NOISY_AUDIO_DIR $CLEAN_AUDIO_DIR $ENROLLMENT_DIR \
    $PREPARED_DATA_DIR/noisy $PREPARED_DATA_DIR/clean $PREPARED_DATA_DIR/enrollment

  # Here the data will be splitted into train/dev/eval sets.
  for audio_type in noisy clean enrollment; do
    local/split_data.sh $PREPARED_DATA_DIR/$audio_type $DATA_DIR/$audio_type local
  done
fi
#stage=100500

# Embeddings preparation.
if [ $stage -le 4 ]; then
  for dset in train; do
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/xvectors/mfcc.conf \
      --pitch-config conf/xvectors/pitch.conf --nj 2 --cmd "$train_cmd" $DATA_DIR/enrollment/$dset

    sid/compute_vad_decision.sh --nj 2 --cmd "$train_cmd" --vad-config conf/xvectors/vad.conf \
      $DATA_DIR/enrollment/$dset

    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd --mem 4G" --nj 4 \
      --use-gpu $use_gpu $EMBEDDING_NNET_DIR $DATA_DIR/enrollment/$dset \
      $DATA_DIR/xvectors/"$dset"_orig
  done
fi
#stage=100500

XVECTORS_DIR_SUFFIX="_orig"
if $DO_PCA; then
  XVECTORS_DIR_SUFFIX=""
fi

if [ $stage -le 5 ] && $DO_PCA; then
  for dset in train; do
    est-pca --read-vectors=true --dim=$PCA_DIM scp:$DATA_DIR/xvectors/"$dset"_orig/xvector.scp \
      $DATA_DIR/xvectors/"$dset"_orig/pca$PCA_DIM.mat
    mkdir -p $DATA_DIR/xvectors/$dset
    transform-vec $DATA_DIR/xvectors/"$dset"_orig/pca$PCA_DIM.mat scp:$DATA_DIR/xvectors/"$dset"_orig/xvector.scp \
      ark,scp:$DATA_DIR/xvectors/$dset/xvector.ark,$DATA_DIR/xvectors/$dset/xvector.scp
  done
fi
#stage=100500


# Feature extraction.
if [ $stage -le 6 ]; then
  for dset in train; do
    for audio_type in noisy clean; do
      steps/make_fbank.sh --nj 4 --compress false --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;

      utils/fix_data_dir.sh $DATA_DIR/$audio_type/$dset
    done

    mkdir -p $FEATURES_DIR/$dset
    local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset \
      $DATA_DIR/xvectors/$dset$XVECTORS_DIR_SUFFIX $FEATURES_DIR/$dset \
      $LOGS_DIR --cmd "$train_cmd" --nj 16

#    append-xvectors scp:$DATA_DIR/xvectors/$dset$XVECTORS_DIR_SUFFIX/xvector.scp ark:$DATA_DIR/noisy/$dset/utt2spk \
#      scp:$DATA_DIR/noisy/$dset/feats.scp ark,scp:$FEATURES_DIR/$dset/feats.ark,$FEATURES_DIR/$dset/feats.scp

  done
fi
#stage=100500

# Train nnet
if [ $stage -le 7 ]; then
  utils/fix_data_dir.sh $FEATURES_DIR/train
  local/train_voice_filter.sh $FEATURES_DIR/train $DATA_DIR/clean/train/feats.scp $VF_NNET_DIR \
    --cmd "$train_cmd"
fi
stage=100500


# Evaluate
if $calculate_error && [ $stage -le 8 ]; then
  for dset in dev eval; do
    # Prepare embedding.
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/xvectors/mfcc.conf \
      --pitch-config conf/xvectors/pitch.conf --nj 2 --cmd "$train_cmd --mem 4G" $DATA_DIR/enrollment/$dset
    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/compute_vad_decision.sh --nj 2 --cmd "$train_cmd --mem 4G" --vad-config conf/xvectors/vad.conf \
      $DATA_DIR/enrollment/$dset

    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd --mem 4G" --nj 4 \
      --use-gpu $use_gpu $EMBEDDING_NNET_DIR $DATA_DIR/enrollment/$dset \
      $DATA_DIR/xvectors/$dset

    # Feature extraction.
    for audio_type in noisy clean; do
      steps/make_fbank.sh --nj 16 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset
      utils/fix_data_dir.sh $DATA_DIR/$audio_type/$dset
    done

    # Prepare input for the nnet.
    local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset \
      $DATA_DIR/xvectors/$dset$XVECTORS_DIR_SUFFIX $FEATURES_DIR/$dset \
      $LOGS_DIR --cmd "$train_cmd" --nj 16

    # Get the nnet output for the set.
    local/compute_output.sh $FEATURES_DIR/$dset $VF_NNET_DIR $VF_NNET_DIR/"$dset"_output \
      --use-gpu $use_gpu --cmd "$decode_cmd" --nj 10 || exit 1;

    copy-feats scp:$VF_NNET_DIR/"$dset"_output/output.scp ark,t:$VF_NNET_DIR/"$dset"_output/feats_matrix
    local/compute_objective.py --predictions-dir $VF_NNET_DIR/"$dset"_output --ground-truth-dir $DATA_DIR/clean/$dset
  done
fi

if [ $stage -le 9 ]; then
  local/decode.sh --stage $stage --mic $mic --do-pca $DO_PCA "$DECODE_SETS" $ENROLLMENT_DIR $VF_NNET_DIR
fi

exit 0;
