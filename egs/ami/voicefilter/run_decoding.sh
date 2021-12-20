#!/usr/bin/env bash
# Runs decoding with voice filter.
# Author: Hanna Kartynnik (hk3129).

. ./cmd.sh
. ./path.sh


stage=2
mic=ihm
do_pca=false
pca_dim=128

# Subset of the original dev dataset.
DECODE_SETS="dev"
MUSAN_ROOT="musan_corpora"
AMI_AUDIO_DIR="../s5b/wav_db"
AMI_ANNOTATIONS_DIR="../s5b/data/local/downloads/annotations"
CLEAN_AUDIO_DIR="demo/data/audio/clean"
ENROLLMENT_DIR="demo/data/audio/clean"
EMBEDDING_NNET_DIR="voxceleb_trained"
PREPARED_DATA_DIR="demo/data/prepared"
DATA_DIR="demo/data/processed"
VF_NNET_DIR="exp_log_fbanks"

# Chunk length for voice filter (in seconds)
CHUNK_LENGTH=3

if [ ! -d $AMI_AUDIO_DIR ]; then
  echo "There is no audio data has been found. Please download"
  exit 1;
fi

if [ ! -d $AMI_ANNOTATIONS_DIR ]; then
  echo "There is no transcript data found. Running ../s5b/run_prepare_shared.sh"
  ../s5b/run_prepare_shared.sh
fi

# Prepare original data directories for s5b recipe data/ihm/train_orig, etc.
# Do stage 2 in s5b

if [ $stage -le 1 ]; then
  python3 local/clean_audio_extractor.py --audio-folder $AMI_AUDIO_DIR --annotations-folder $AMI_ANNOTATIONS_DIR \
    --output-folder $CLEAN_AUDIO_DIR --logs-folder logs_decoding/extraction --offset 100 \
    --enrollment-duration-threshold 3000 \
    --chunk-length $CHUNK_LENGTH --combine --num-jobs 2
fi

if [ $stage -le 2 ]; then
  local/decode.sh --stage 11 --mic ihm --do-pca false "$DECODE_SETS" $ENROLLMENT_DIR $VF_NNET_DIR
fi

exit 0;
