#!/usr/bin/env bash

. ./cmd.sh
. ./path.sh


MUSAN_ROOT="musan_corpora"
AMI_AUDIO_DIR="amicorpus"
AMI_ANNOTATIONS_DIR="annotations"
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
VF_NNET_DIR="exp_log_fbanks"
# Chunk length for voice filter (in seconds)
CHUNK_LENGTH=3
DO_PCA=false


stage=6

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
  #python3 local/clean_audio_extractor.py --audio-folder $AMI_AUDIO_DIR --annotations-folder $AMI_ANNOTATIONS_DIR \
  #  --output-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/extraction --offset 100 --enrollment-duration-threshold 3000 \
  #  --chunk-length $CHUNK_LENGTH --combine --num-jobs 32
  python3 local/split_mix_audio.py --clean-audio-folder $CLEAN_AUDIO_DIR --logs-folder $LOGS_DIR/mix \
    --mix-folder $NOISY_AUDIO_DIR --chunk-length $CHUNK_LENGTH --add-other-noise \
    --musan-folder $MUSAN_ROOT/musan --num-jobs 32
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
  #cat local/split_dev.orig local/split_eval.orig | sort -u > local/split_test.orig
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
      --pitch-config conf/xvectors/pitch.conf --nj 32 --cmd "$train_cmd --mem 4G" $DATA_DIR/enrollment/$dset
    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/compute_vad_decision.sh --nj 32 --cmd "$train_cmd --mem 4G" --vad-config conf/xvectors/vad.conf \
      $DATA_DIR/enrollment/$dset

    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd --mem 4G" --nj 4 \
      --use-gpu wait $EMBEDDING_NNET_DIR $DATA_DIR/enrollment/$dset \
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
    est-pca --read-vectors=true --dim=256 scp:$DATA_DIR/xvectors/"$dset"_orig/xvector.scp $DATA_DIR/xvectors/"$dset"_orig/pca256.mat
    mkdir -p $DATA_DIR/xvectors/$dset
    transform-vec $DATA_DIR/xvectors/"$dset"_orig/pca256.mat scp:$DATA_DIR/xvectors/"$dset"_orig/xvector.scp \
      ark,scp:$DATA_DIR/xvectors/$dset/xvector.ark,$DATA_DIR/xvectors/$dset/xvector.scp
  done
fi
#stage=100500


# Feature extraction.
if [ $stage -le 6 ]; then
  for dset in train; do
    for audio_type in noisy clean; do
      steps/make_fbank.sh --nj 16 --compress false --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;
      #steps/make_mfcc.sh --nj 15 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;
      #steps/make_mfcc.sh --mfcc-config conf/mfcc_hires80.conf --nj 20 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset || exit 1;
      #steps/compute_cmvn_stats.sh $DATA_DIR/$audio_type/$dset
      #compute-spectrogram-feats --return-raw-fft=true --write-utt2dur=ark,t:$DATA_DIR/$audio_type/$dset/utt2dur  --verbose=2 \
      #  scp,p:$DATA_DIR/$audio_type/$dset/wav.scp ark,scp:$DATA_DIR/$audio_type/$dset/raw_sg_feats.ark,$DATA_DIR/$audio_type/$dset/feats.scp
      #cp $DATA_DIR/$audio_type/$dset/feats.scp $DATA_DIR/$audio_type/$dset/feats_sp.scp
      #local/fbank_to_mfcc.sh --nj 16 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset

      utils/fix_data_dir.sh $DATA_DIR/$audio_type/$dset
    done

    #mkdir -p $FEATURES_DIR/$dset
    #local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset \
    #  $DATA_DIR/xvectors/$dset$XVECTORS_DIR_SUFFIX $FEATURES_DIR/$dset \
    #  $LOGS_DIR --cmd "$train_cmd" --nj 16

    append-xvectors scp:$DATA_DIR/xvectors/$dset$XVECTORS_DIR_SUFFIX/xvector.scp ark:$DATA_DIR/noisy/$dset/utt2spk \
      scp:$DATA_DIR/noisy/$dset/feats.scp ark,scp:$FEATURES_DIR/$dset/feats.ark,$FEATURES_DIR/$dset/feats.scp

  done
fi
#stage=100500

if [ $stage -le -1 ]; then
  for dset in train; do
    # Made dimensionality reduction for xvectors.
    if [ ! -d $DATA_DIR/xvectors_orig ]; then
      mkdir $DATA_DIR/xvectors_orig
      cp -r $DATA_DIR/xvectors/$dset $DATA_DIR/xvectors_orig/$dset
      sed -i 's/xvectors/xvectors_orig/g' $DATA_DIR/xvectors_orig/$dset/xvector.scp
      rm -r $DATA_DIR/xvectors/$dset 
    fi
    [ ! -d $DATA_DIR/xvectors/$dset ] && mkdir -p $DATA_DIR/xvectors/$dset
    est-pca --dim=64 --read-vectors=true scp:$DATA_DIR/xvectors_orig/$dset/xvector.scp $DATA_DIR/xvectors_orig/$dset/pca64.mat || exit 1;
    transform-vec $DATA_DIR/xvectors_orig/$dset/pca64.mat scp:$DATA_DIR/xvectors_orig/$dset/xvector.scp \
      ark,scp:$DATA_DIR/xvectors/$dset/xvector.ark,$DATA_DIR/xvectors/$dset/xvector.scp || exit 1;
    mkdir -p $FEATURES_DIR/$dset || exit 1;
    local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset $DATA_DIR/xvectors/$dset $FEATURES_DIR/$dset \
      $LOGS_DIR --cmd "$train_cmd" --nj 16

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
if [ $stage -le 8 ]; then
  for dset in dev "eval"; do
    # Prepare embedding.
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/xvectors/mfcc.conf \
      --pitch-config conf/xvectors/pitch.conf --nj 32 --cmd "$train_cmd --mem 4G" $DATA_DIR/enrollment/$dset
    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/compute_vad_decision.sh --nj 32 --cmd "$train_cmd --mem 4G" --vad-config conf/xvectors/vad.conf \
      $DATA_DIR/enrollment/$dset

    utils/fix_data_dir.sh $DATA_DIR/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd --mem 4G" --nj 4 \
      --use-gpu wait $EMBEDDING_NNET_DIR $DATA_DIR/enrollment/$dset \
      $DATA_DIR/xvectors/$dset

    # Feature extraction.
    for audio_type in noisy clean; do
      steps/make_fbank.sh --nj 16 --cmd "$train_cmd" $DATA_DIR/$audio_type/$dset
      utils/fix_data_dir.sh $DATA_DIR/$audio_type/$dset
    done

    # Prepare input for the nnet.
    mkdir -p $FEATURES_DIR/$dset || exit 1;
    local/append_noisy_and_xvectors.sh $DATA_DIR/noisy/$dset $DATA_DIR/xvectors/$dset $FEATURES_DIR/$dset \
      $LOGS_DIR --cmd "$train_cmd" --nj 16

    # Get the nnet output for the set.
    #utils/fix_data_dir.sh $FEATURES_DIR/$dset
    #local/evaluate.sh $FEATURES_DIR/$dset $VF_NNET_DIR $VF_NNET_DIR/"$dset"_output \
    #  --use-gpu true --cmd "$decode_cmd" --nj 10 || exit 1;
  done
fi

if [ $stage -le 9 ]; then
  for dset in dev; do
    # Get the nnet output for the set.
    local/evaluate.sh $FEATURES_DIR/$dset $VF_NNET_DIR $VF_NNET_DIR/"$dset"_output \
      --use-gpu true --cmd "$decode_cmd" --nj 10 || exit 1;

    copy-feats scp:$VF_NNET_DIR/"$dset"_output/output.scp ark,t:$VF_NNET_DIR/"$dset"_output/feats_matrix
    #copy-feats scp:$DATA_DIR/clean/$dset/feats.scp ark,t:$DATA_DIR/clean/$dset/feats_matrix
    local/compute_objective.py --predictions-dir $VF_NNET_DIR/"$dset"_output --ground-truth-dir $DATA_DIR/clean/$dset
  done
fi


