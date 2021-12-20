#!/usr/bin/env bash

stage=9
mic=ihm
do_pca=false
pca_dim=128
DECODE_SETS=demo
ENROLLMENT_DIR=data/audio/clean
VF_NNET_DIR=exp

. utils/parse_options.sh

DECODE_SETS=$1
ENROLLMENT_DIR=$2
VF_NNET_DIR=$3

AMI_RECIPE_DATA_DIR=../s5b/data/$mic
mkdir -p data/$mic

if [ $stage -le 9 ]; then
  echo "Preraring enrollment data for decoding set(s)."
  temp_dir=data/temp
  mkdir -p $temp_dir
  for dset in $DECODE_SETS; do
    if [ ! -d $AMI_RECIPE_DATA_DIR ] || [ ! -d $AMI_RECIPE_DATA_DIR/$dset ]; then
      echo "Run s5b recipe first."
      exit 1;
    fi
    mkdir -p data/$mic/enrollment/$dset
    #AMI_EN2002a_H00
    # We assume 
    awk '{print $1}' $AMI_RECIPE_DATA_DIR/$dset/feats.scp > $temp_dir/uttids
    awk '{print $1}' $AMI_RECIPE_DATA_DIR/$dset/wav.scp | sort -u - > $temp_dir/spkids
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

    cp $temp_dir/"$dset"_enrollment_wav.scp data/$mic/enrollment/$dset/wav.scp
  done
  echo "Finished data preparation for enrollment"
fi
#stage=100500

if [ $stage -le 10 ]; then
  echo "Embedding preparation for decoding sets."
  mkdir -p data/$mic/xvectors
  #emb_cmd=run.pl
  for dset in $DECODE_SETS; do
    steps/make_mfcc_pitch.sh --write-utt2num-frames true --mfcc-config conf/xvectors/mfcc.conf \
      --pitch-config conf/xvectors/pitch.conf --nj 10 --cmd "$train_cmd" \
      data/$mic/enrollment/$dset

    utils/fix_data_dir.sh data/$mic/enrollment/$dset

    sid/compute_vad_decision.sh --nj 10 --cmd "$train_cmd" \
      --vad-config conf/xvectors/vad.conf data/$mic/enrollment/$dset

    sid/nnet3/xvector/extract_xvectors.sh --cmd "$train_cmd" --nj 10 \
      voxceleb_trained data/$mic/enrollment/$dset data/$mic/xvectors/"$dset"_orig
  done
fi

XVECTORS_DIR_SUFFIX="_orig"
if  $do_pca; then
  XVECTORS_DIR_SUFFIX=""
fi

if [ $stage -le 11 ] && $do_pca; then
  for dset in $DECODE_SETS; do
    est-pca --read-vectors=true --dim=$pca_dim scp:data/$mic/xvectors/"$dset"_orig/xvector.scp \
      data/$mic/xvectors/"$dset"_orig/pca$pca_dim.mat
    mkdir -p data/$mic/xvectors/$dset
    transform-vec data/$mic/xvectors/"$dset"_orig/pca$pca_dim.mat scp:data/$mic/xvectors/"$dset"_orig/xvector.scp \
      ark,scp:data/$mic/xvectors/$dset/xvector.ark,data/$mic/xvectors/$dset/xvector.scp
  done
fi

#stage=100500
features_dir=data/$mic/with_embedding
if [ $stage -le 11 ]; then
  mkdir -p logs_vf

  for dset in $DECODE_SETS; do
    # Create fbanks
    mkdir -p data/$mic/"$dset"_fbank
    for f in glm reco2file_and_channel segments spk2utt stm text utt2dur utt2num_frames utt2spk wav.scp; do
      cp $AMI_RECIPE_DATA_DIR/$dset/$f data/$mic/"$dset"_fbank/$f
    done

    # We use --compress false since eventually we convert these fbanks to mfcc after applying VF model.
    steps/make_fbank.sh --fbank-config conf/fbank.conf --nj 8 --compress false \
      --cmd "$train_cmd" data/$mic/"$dset"_fbank
    utils/fix_data_dir.sh data/$mic/"$dset"_fbank

    mkdir -p $features_dir/$dset
    #append-xvectors scp:data/$mic/xvectors/$dset$XVECTORS_DIR_SUFFIX/xvector.scp ark:data/$mic/enrollment/$dset/utt2spk_orig \
    #  scp:data/$mic/"$dset"_fbank/feats.scp ark,scp:$features_dir/$dset/feats.ark,$features_dir/$dset/feats.scp
    local/append_noisy_and_xvectors.sh data/$mic/"$dset"_fbank data/xvectors/$dset$XVECTORS_DIR_SUFFIX \
      $features_dir/$dset logs_vf --cmd "$train_cmd"
    echo "appended"

    #mkdir -p "$dset"_vf
    cp -r data/$mic/"$dset"_fbank data/$mic/"$dset"_vf
  done
fi
#stage=100500

output_dir=data/$mic/"$dset"_vf/exp_fbanks
output_name=exp_fbanks
if [ $stage -le 12 ]; then
  for dset in $DECODE_SETS; do
    for f in spk2utt utt2spk; do
      cp data/$mic/"$dset"_fbank/$f $features_dir/$dset/$f
    done
    utils/fix_data_dir.sh $features_dir/$dset
    mkdir -p $output_dir
    local/evaluate.sh --cmd "$decode_cmd" --nj 8 --use-gpu $use_gpu \
      $features_dir/$dset exp_fbanks $output_dir || exit 1;
    echo "used vf model"
    cp $output_dir/output.scp $output_dir/feats_fbank.scp
    for f in glm reco2file_and_channel segments spk2utt stm text utt2dur utt2num_frames utt2spk wav.scp; do
      cp data/$mic/"$dset"_vf/$f $output_dir/$f
    done
    #for f in segments text utt2dur utt2num_frames utt2spk; do
    #  awk '{print $1;}' data/with_embedding/$dset/feats.scp | join -1 1 -2 1 - $output_dir/$f > $output_dir/"$f"_temp
    #  cp $output_dir/"$f"_temp $output_dir/$f
    #  rm $output_dir/"$f"_temp
    #done
    #utils/utt2spk_to_spk2utt.pl <$output_dir/utt2spk >$output_dir/spk2utt || exit 1;
  done
fi
#stage=100500

if [ $stage -le 13 ]; then
  for dset in $DECODE_SETS; do
    utils/fix_data_dir.sh $output_dir
    # Here we convert fbank features attained after applying VF model to MFCC features
    # expected by ASR model.
    # Note: It's important to have the same number of jobs as when making original fbanks!
    local/fbank_to_mfcc.sh --mfcc-config conf/mfcc_hires80.conf --nj 8 \
      --cmd "$train_cmd" $output_dir
  done
fi
#stage=100500

if [ $stage -le 14 ]; then
  for dset in $DECODE_SETS; do
    #api_opt=
    #[ "$mic" != "ihm" ] && ali_opt="--use-ihm-ali true"
    utils/fix_data_dir.sh $output_dir
    local/evaluate.sh $output_dir $output_name $dset --mic $mic
  done
fi

exit 0