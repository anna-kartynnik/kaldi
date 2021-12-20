#!/usr/bin/env bash

# Decoding code taken from ../../s5b/local/chain/run_tdnn.sh


set -e -o pipefail
# First the options that are passed through to run_ivector_common.sh
# (some of which are also used in this script directly).
stage=18
mic=ihm
nj=2
min_seg_len=1.55
use_ihm_ali=false
train_set=train_cleaned # train_cleaned
gmm=tri3_cleaned  # the gmm for the target data
ihm_gmm=tri3  # the gmm for the IHM system (if --use-ihm-ali true).
#num_threads_ubm=32
#ivector_transform_type=pca
nnet3_affix=_cleaned  # cleanup affix for nnet3 and chain dirs, e.g. _cleaned
#num_epochs=15
#remove_egs=true

# The rest are configs specific to this script.  Most of the parameters
# are just hardcoded at this level, in the commands below.
#train_stage=-10
tree_affix=  # affix for tree directory, e.g. "a" or "b", in case we change the configuration.
tdnn_affix=1j  #affix for TDNN directory, e.g. "a" or "b", in case we change the configuration.
#common_egs_dir=  # you can set this to use previously dumped egs.
#dropout_schedule='0,0@0.20,0.5@0.50,0'

# End configuration section.
echo "$0 $@"  # Print the command line for logging

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh


# if ! cuda-compiled; then
#   cat <<EOF && exit 1
# This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
# If you want to use GPUs (and have them), go to src/, and configure and make on a machine
# where "nvcc" is installed.
# EOF
# fi

#local/chain/run_ivector_common.sh --stage 0 \
#                                  --mic $mic \
#                                  --nj $nj \
#                                  --hires_suffix 80 \
#                                  --min-seg-len $min_seg_len \
#                                  --train-set $train_set \
#                                  --gmm $gmm \
#                                  --num-threads-ubm $num_threads_ubm \
#                                  --ivector-transform-type "$ivector_transform_type" \
#                                  --nnet3-affix "$nnet3_affix"

# # Note: the first stage of the following script is stage 8.
# local/nnet3/prepare_lores_feats.sh --stage $stage \
#                                    --mic $mic \
#                                    --nj $nj \
#                                    --min-seg-len $min_seg_len \
#                                    --use-ihm-ali $use_ihm_ali \
#                                    --train-set $train_set

# if $use_ihm_ali; then
#   gmm_dir=../../s5b/exp/ihm/${ihm_gmm}
#   ali_dir=exp/${mic}/${ihm_gmm}_ali_${train_set}_sp_comb_ihmdata
#   lores_train_data_dir=data/$mic/${train_set}_ihmdata_sp_comb
#   tree_dir=exp/$mic/chain${nnet3_affix}/tree_bi${tree_affix}_ihmdata
#   lat_dir=exp/$mic/chain${nnet3_affix}/${gmm}_${train_set}_sp_comb_lats_ihmdata
#   dir=exp/$mic/chain${nnet3_affix}/tdnn${tdnn_affix}_sp_bi_ihmali
#   # note: the distinction between when we use the 'ihmdata' suffix versus
#   # 'ihmali' is pretty arbitrary.
# else
#   gmm_dir=../../s5b/exp/${mic}/$gmm
#   ali_dir=../../s5b/exp/${mic}/${gmm}_ali_train_cleaned_sp_comb
#   lores_train_data_dir=../../s5b/data/$mic/${train_set}_sp_comb
#   tree_dir=../../s5b/exp/$mic/chain${nnet3_affix}/tree_bi${tree_affix}
#   lat_dir=exp/$mic/chain${nnet3_affix}/${gmm}_${train_set}_sp_comb_lats
#   dir=../../s5b/exp/$mic/chain${nnet3_affix}/tdnn${tdnn_affix}_sp_bi
# #fi

# train_data_dir=data/$mic/${train_set}_sp_hires_comb
# train_ivector_dir=exp/$mic/nnet3${nnet3_affix}/ivectors_${train_set}_sp_hires_comb
# final_lm=`cat data/local/lm/final_lm`
# LM=$final_lm.pr1-7


# for f in $gmm_dir/final.mdl $lores_train_data_dir/feats.scp \
#    $train_data_dir/feats.scp $train_ivector_dir/ivector_online.scp; do
#   [ ! -f $f ] && echo "$0: expected file $f to exist" && exit 1
# done


# if [ $stage -le 11 ]; then
#   if [ -f $ali_dir/ali.1.gz ]; then
#     echo "$0: alignments in $ali_dir appear to already exist.  Please either remove them "
#     echo " ... or use a later --stage option."
#     exit 1
#   fi
#   echo "$0: aligning perturbed, short-segment-combined ${maybe_ihm}data"
#   steps/align_fmllr.sh --nj $nj --cmd "$train_cmd" \
#      ${lores_train_data_dir} data/lang $gmm_dir $ali_dir
# fi

# [ ! -f $ali_dir/ali.1.gz ] && echo  "$0: expected $ali_dir/ali.1.gz to exist" && exit 1

# if [ $stage -le 12 ]; then
#   echo "$0: creating lang directory with one state per phone."
#   # Create a version of the lang/ directory that has one state per phone in the
#   # topo file. [note, it really has two states.. the first one is only repeated
#   # once, the second one has zero or more repeats.]
#   if [ -d data/lang_chain ]; then
#     if [ data/lang_chain/L.fst -nt data/lang/L.fst ]; then
#       echo "$0: data/lang_chain already exists, not overwriting it; continuing"
#     else
#       echo "$0: data/lang_chain already exists and seems to be older than data/lang..."
#       echo " ... not sure what to do.  Exiting."
#       exit 1;
#     fi
#   else
#     cp -r data/lang data/lang_chain
#     silphonelist=$(cat data/lang_chain/phones/silence.csl) || exit 1;
#     nonsilphonelist=$(cat data/lang_chain/phones/nonsilence.csl) || exit 1;
#     # Use our special topology... note that later on may have to tune this
#     # topology.
#     steps/nnet3/chain/gen_topo.py $nonsilphonelist $silphonelist >data/lang_chain/topo
#   fi
# fi

# if [ $stage -le 13 ]; then
#   # Get the alignments as lattices (gives the chain training more freedom).
#   # use the same num-jobs as the alignments
#   steps/align_fmllr_lats.sh --nj 100 --cmd "$train_cmd" ${lores_train_data_dir} \
#     data/lang $gmm_dir $lat_dir
#   rm $lat_dir/fsts.*.gz # save space
# fi

# if [ $stage -le 14 ]; then
#   # Build a tree using our new topology.  We know we have alignments for the
#   # speed-perturbed data (local/nnet3/run_ivector_common.sh made them), so use
#   # those.
#   if [ -f $tree_dir/final.mdl ]; then
#     echo "$0: $tree_dir/final.mdl already exists, refusing to overwrite it."
#     exit 1;
#   fi
#   steps/nnet3/chain/build_tree.sh --frame-subsampling-factor 3 \
#       --context-opts "--context-width=2 --central-position=1" \
#       --leftmost-questions-truncate -1 \
#       --cmd "$train_cmd" 4200 ${lores_train_data_dir} data/lang_chain $ali_dir $tree_dir
# fi


graph_dir=$dir/graph_${LM}

if [ $stage -le 18 ]; then
  rm $dir/.error 2>/dev/null || true
  features_to_decode_folder=$1
  set_name=$2
  dset=$3
  (
    ../../s5b/steps/nnet3/decode.sh --acwt 1.0 --post-decode-acwt 10.0 \
      --nj $nj --cmd "$decode_cmd" \
      --online-ivector-dir ../../s5b/exp/$mic/nnet3${nnet3_affix}/ivectors_${dset}_hires \
      --scoring-opts "--min-lmwt 5 " \
      $graph_dir $features_to_decode_folder decode_${dset}_${set_name} || exit 1;
  ) || touch $dir/.error &
  
  wait
  if [ -f $dir/.error ]; then
    echo "$0: something went wrong in decoding"
    exit 1
  fi
fi
exit 0


