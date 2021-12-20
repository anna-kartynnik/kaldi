#!/bin/bash
# Main training script.
# hk3129: Authored by me.

set -e

config_nnet=1
train_nnet=1

nj=2
cmd=run.pl

echo "$0 $@"  # Print the command line for logging.

if [ -f path.sh ]; then . ./path.sh; fi
num_epochs=3

data_dir=$1
targets_scp=$2
exp_dir=$3

mkdir -p $exp_dir


if [ "$config_nnet" -eq "1" ]; then

    mkdir -p $exp_dir/configs
    mkdir -p $exp_dir/egs

    target_dim=`feat-to-dim scp:$targets_scp -`
    fbank_dim=$target_dim
    feat_dim=$fbank_dim
    num_targets=$feat_dim

    xvector_dim=512
    embedding_dim=128
    lstm_output_dim=200
    fc1_dim=$target_dim
    fc_dim=$target_dim
    input_dim=$(($target_dim + $xvector_dim))

    # The following definition is for the voice filter model
    cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$input_dim name=input

dim-range-component name=fbanks input=input dim=$target_dim dim-offset=0
dim-range-component name=speaker_embedding input=input dim=$xvector_dim dim-offset=$target_dim

# this takes the MFCCs and generates filterbank coefficients. The MFCCs
# are more compressible so we prefer to dump the MFCCs to disk rather
# than filterbanks.
#idct-layer name=idct input=mfcc dim=$feat_dim cepstral-lifter=22 affine-transform-file=$exp_dir/configs/idct.mat
#batchnorm-component name=fbanks input=fbanks_lin

batchnorm-layer name=embedding input=speaker_embedding dim=$embedding_dim
batchnorm-layer name=fbanks_norm input=fbanks
#renorm-component name=fbanks input=fbanks_lin
#renorm-component name=embedding input=speaker_embedding

conv-relu-batchnorm-layer name=conv1 input=fbanks_norm height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-3,-2,-1,0,1,2,3 time-offsets=0
conv-relu-batchnorm-layer name=conv2 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=0 time-offsets=-3,-2,-1,0,1,2,3
conv-relu-batchnorm-layer name=conv3 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-2,-1,0,1,2
#conv-relu-batchnorm-layer name=conv4 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-4,-2,0,2,4
#conv-relu-batchnorm-layer name=conv5 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-8,-4,0,4,8
#conv-relu-batchnorm-layer name=conv6 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-16,-8,0,8,16
#conv-relu-batchnorm-layer name=conv7 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-32,-16,0,16,32
conv-relu-batchnorm-layer name=conv8 height-in=$feat_dim height-out=$feat_dim num-filters-out=8 height-offsets=0 time-offsets=0

lstm-layer name=lstmforward input=Append(conv8, embedding) cell-dim=$lstm_output_dim delay=-1
#l2-regularize=0.01
#relu-renorm-layer name=lstmforward dim=$lstm_output_dim input=Append(0, IfDefined(-1))
lstm-layer name=lstmbackward input=Append(conv8, embedding) cell-dim=$lstm_output_dim delay=1
# l2-regularize=0.01
#relu-renorm-layer name=lstmbackward dim=$lstm_output_dim input=Append(0, IfDefined(1))

#lstm-layer name=lstmforward input=Append(batchnorm0, embedding) cell-dim=$lstm_output_dim delay=-1
#lstm-layer name=lstmbackward input=Append(batchnorm0, embedding) cell-dim=$lstm_output_dim delay=1

relu-layer name=lstmrelu input=Append(lstmforward, lstmbackward)

relu-layer name=fc1 input=lstmrelu dim=$fc1_dim
#relu-layer name=fc1 input=Append(conv8,embedding) dim=$fc1_dim
#relu-layer name=fc1 input=Append(lstmforward, lstmbackward) dim=$fc1_dim

sigmoid-layer name=fc2 input=fc1 dim=$fc_dim
#linear-component name=fc2 input=fc1 dim=$fc_dim

# component name=elementwiseproduct type=ElementwiseProductComponent input-dim=$(($fc_dim * 2)) output-dim=$fc_dim
# component-node name=elementwiseproduct component=elementwiseproduct  input=Append(mfcc,fc2.sigmoid)
output name=output dim=$fc_dim input=fc2 objective-type=quadratic
#output-layer name=output dim=$fc_dim input=fc2 objective-type=quadratic l2-regularize=0.0001 include-log-softmax=false
EOF
    
    steps/nnet3/xconfig_to_configs.py \
        --xconfig-file $exp_dir/configs/network.xconfig \
        --config-dir $exp_dir/configs/

    nnet_config_file=$exp_dir/configs/final.config
    # Save the last `output` node.
    output_config=`tail $nnet_config_file -n 1`
    # Remove last `output` node.
    sed -i '$d' $nnet_config_file
    # Add element-wise product component.
    echo "component name=elementwiseproduct type=ElementwiseProductComponent input-dim=$(($fc_dim * 2)) output-dim=$fc_dim" >> $nnet_config_file
    echo "component-node name=elementwiseproduct component=elementwiseproduct  input=Append(fbanks,fc2.sigmoid)" >> $nnet_config_file
    echo "output-node name=output input=elementwiseproduct objective=quadratic" >> $nnet_config_file
    
fi

if [ "$train_nnet" -eq "1" ]; then
    steps/nnet3/train_raw_dnn.py \
        --stage=-5 \
        --cmd="$cmd" \
        --nj=$nj \
        --trainer.num-epochs=$num_epochs \
        --trainer.optimization.num-jobs-initial=1 \
        --trainer.optimization.num-jobs-final=4 \
        --trainer.optimization.initial-effective-lrate=0.001 \
        --trainer.optimization.minibatch-size=64 \
        --trainer.shuffle-buffer-size=1000 \
        --cleanup.preserve-model-interval=20 \
        --egs.frames-per-eg=8 \
        --trainer.samples-per-iter=50000 \
        --trainer.max-param-change=2.0 \
        --trainer.srand=0 \
        --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
        --feat-dir=$data_dir \
        --use-dense-targets=true \
        --targets-scp=$targets_scp \
        --cleanup.remove-egs=true \
        --use-gpu=yes \
        --dir=$exp_dir  \
        --report-key="objective" \
        || exit 1;
fi
