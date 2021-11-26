#!/bin/bash

# [TODO] documentation
# [TODO] license
#


config_nnet=0
# make_egs=0
# combine_egs=1
train_nnet=1
# make_copies_nnet=1
# decode_test=1


set -e

# Begin configuration section.
nj=4
cmd=run.pl

# End configuration section.

echo "$0 $@"  # Print the command line for logging.

if [ -f path.sh ]; then . ./path.sh; fi
#. parse_options.sh || exit 1;

# if [ $# -lt 1 ] || [ $# -gt 3 ]; then
# # [TODO] documentation
#   cat >&2 <<EOF
# Usage: $0 [options] <data-dir> [<log-dir> [<fbank-dir>] ]
#  e.g.: $0 data/train
# Note: <log-dir> defaults to <data-dir>/log, and
#       <fbank-dir> defaults to <data-dir>/data
# Options:
#   --nj <nj>                            # number of parallel jobs.
#   --cmd <run.pl|queue.pl <queue opts>> # how to run jobs.
# EOF
#    exit 1;
# fi


# task_list=($1) # space-delimited list of input_dir names
# typo_list=($2) # space-delimited list of "mono" or "tri"
# task2weight=$3 # comma-delimited list of weights for target-vectors
# hidden_dim=$4  # number of hidden dimensions in NNET
# num_epochs=$5  # number of epochs through data
# main_dir=$6    # location of /data and /exp dir (probably "MTL")

#hidden_dim=128
num_epochs=2

data_dir=$1  # like data/train_orig/noisy
targets_scp=$2 # like data/train_orig/clean/feats.scp
#embedding_dir=$3
exp_dir=$3
#master_egs_dir=$exp_dir/egs





if [ "$config_nnet" -eq "1" ]; then

    echo "### ============================ ###";
    echo "### CREATE CONFIG FILES FOR NNET ###";
    echo "### ============================ ###";

    ## Remove old generated files
    # rm -rf $exp_dir
    # for i in `seq 0 $[$num_tasks-1]`; do
    #     rm -rf exp/${task_list[$i]}/nnet3
    # done

    mkdir -p $exp_dir/configs
    # ?
    mkdir -p $exp_dir/egs

    #feat_dim=`feat-to-dim scp:$data_dir/feats.scp -`
    feat_dim=`feat-to-dim scp:$targets_scp -`
    num_targets=$feat_dim

    #hidden_dim=$hidden_dim
    xvector_dim=512
    embedding_dim=128
    lstm_output_dim=400
    fc_dim=$feat_dim
    input_dim=$(($feat_dim + $xvector_dim))
    # The following definition is for the voice filter model
    cat <<EOF > $exp_dir/configs/network.xconfig
input dim=$input_dim name=input

dim-range-component name=fbanks input=input dim=$feat_dim dim-offset=0
dim-range-component name=speaker_embedding input=input dim=$xvector_dim dim-offset=$feat_dim

sigmoid-layer name=embedding input=speaker_embedding dim=$embedding_dim 

conv-relu-batchnorm-layer name=conv1 input=fbanks height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-3,-2,-1,0,1,2,3 time-offsets=0
conv-relu-batchnorm-layer name=conv2 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=0 time-offsets=-3,-2,-1,0,1,2,3
conv-relu-batchnorm-layer name=conv3 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-2,-1,0,1,2
conv-relu-batchnorm-layer name=conv4 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-4,-2,0,2,4
conv-relu-batchnorm-layer name=conv5 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-8,-4,0,4,8
conv-relu-batchnorm-layer name=conv6 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-16,-8,0,8,16
conv-relu-batchnorm-layer name=conv7 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-32,-16,0,16,32
conv-relu-batchnorm-layer name=conv8 height-in=$feat_dim height-out=$feat_dim num-filters-out=8 height-offsets=0 time-offsets=0

lstm-layer name=lstmforward input=Append(conv8, embedding) cell-dim=$lstm_output_dim delay=-1
lstm-layer name=lstmbackward input=Append(conv8, embedding) cell-dim=$lstm_output_dim delay=1

relu-layer name=lstmrelu input=Append(lstmforward, lstmbackward)

relu-layer name=fc1 input=lstmrelu dim=$fc_dim
sigmoid-layer name=fc2 input=fc1 dim=$fc_dim
output name=output dim=$fc_dim objective-type=quadratic
EOF
    
    # # Create separate outptut layer and softmax for all tasks.
    
    # for i in `seq 0 $[$num_tasks-1]`;do

    #     num_targets=`tree-info ${multi_ali_dirs[$i]}/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;
    
    #     echo " relu-renorm-layer name=prefinal-affine-task-${i} input=tdnnFINAL dim=$hidden_dim"
    #     echo " output-layer name=output-${i} dim=$num_targets max-change=1.5"
        
    # done >> $exp_dir/configs/network.xconfig
    
    steps/nnet3/xconfig_to_configs.py \
        --xconfig-file $exp_dir/configs/network.xconfig \
        --config-dir $exp_dir/configs/ #\
    #    --nnet-edits="rename-node old-name=output-0 new-name=output"

fi

# relu-renorm-layer name=tdnn1 input=Append(input@-2,input@-1,input,input@1,input@2) dim=$hidden_dim
# relu-renorm-layer name=tdnn2 dim=$hidden_dim
# relu-renorm-layer name=tdnn3 input=Append(-1,2) dim=$hidden_dim
# relu-renorm-layer name=tdnn4 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn5 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn6 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn7 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn8 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn9 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn10 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnn11 input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=tdnnFINAL input=Append(-3,3) dim=$hidden_dim
# relu-renorm-layer name=prefinal-affine input=tdnnFINAL dim=$hidden_dim
# output-layer name=output dim=$num_targets max-change=1.5

# input dim=$embedding_dim name=embedding
# input dim=$feat_dim name=input

# conv-relu-batchnorm-layer name=conv1 input=input height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-3,-2,-1,0,1,2,3 time-offsets=0
# conv-relu-batchnorm-layer name=conv2 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=0 time-offsets=-3,-2,-1,0,1,2,3
# conv-relu-batchnorm-layer name=conv3 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-2,-1,0,1,2
# conv-relu-batchnorm-layer name=conv4 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-4,-2,0,2,4
# conv-relu-batchnorm-layer name=conv5 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-8,-4,0,4,8
# conv-relu-batchnorm-layer name=conv6 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-16,-8,0,8,16
# conv-relu-batchnorm-layer name=conv7 height-in=$feat_dim height-out=$feat_dim num-filters-out=64 height-offsets=-2,-1,0,1,2 time-offsets=-32,-16,0,16,32
# conv-relu-batchnorm-layer name=conv8 height-in=$feat_dim height-out=$feat_dim num-filters-out=8 height-offsets=0 time-offsets=0

# lstm-layer name=lstmforward input=Append(conv8, embedding) cell-dim=$lstm_output_dim delay=-1
# lstm-layer name=lstmbackward input=Append(conv8, embedding) cell-dim=$lstm_output_dim delay=1

# relu-layer name=lstmrelu input=Append(lstmforward, lstmbackward)

# relu-layer name=fc1 input=lstmrelu dim=$fc_dim
# sigmoid-layer name=fc2 input=fc1 dim=$fc_dim
# output-layer name=output dim=$fc_dim include-log-softmax=false objective-type=quadratic


# if [ "$make_egs" -eq "1" ]; then
        
#     echo "### ====================================== ###"
#     echo "### MAKE INDIVIDUAL NNET3 EGS DIR per TASK ###"
#     echo "### ====================================== ###"


#     echo "### MAKE SEPARATE EGS DIR PER TASK ###"
    
#     local/nnet3/prepare_multilingual_egs.sh \
#         --cmd "$cmd" \
#         --cmvn-opts "--norm-means=false --norm-vars=false" \
#         --left-context 30 \
#         --right-context 31 \
#         $num_tasks \
#         ${multi_data_dirs[@]} \
#         ${multi_ali_dirs[@]} \
#         ${multi_egs_dirs[@]} \
#         ${num_targets_list[@]} \
#         || exit 1;

# fi



# if [ "$combine_egs" -eq "1" ]; then

#     echo "### ====================================== ###"
#     echo "### COMBINE ALL TASKS EGS INTO ONE BIG DIR ###"
#     echo "### ====================================== ###"
    
#     steps/nnet3/multilingual/combine_egs.sh \
#         --cmd "$cmd" \
#         --lang2weight $task2weight \
#         $num_tasks \
#         ${multi_egs_dirs[@]} \
#         $master_egs_dir \
#         || exit 1;

# fi



if [ "$train_nnet" -eq "1" ]; then

    echo "### ================ ###"
    echo "### BEGIN TRAIN NNET ###"
    echo "### ================ ###"

    steps/nnet3/train_raw_dnn.py \
        --stage=-5 \
        --cmd="$cmd" \
        --trainer.num-epochs $num_epochs \
        --trainer.optimization.num-jobs-initial=1 \
        --trainer.optimization.num-jobs-final=1 \
        --trainer.optimization.initial-effective-lrate=0.0015 \
        --trainer.optimization.final-effective-lrate=0.00015 \
        --trainer.optimization.minibatch-size=128,23 \
        --trainer.samples-per-iter=50 \
        --trainer.max-param-change=2.0 \
        --trainer.srand=0 \
        --feat.cmvn-opts="--norm-means=false --norm-vars=false" \
        --feat-dir $data_dir \
        --use-dense-targets true \
        --targets-scp $targets_scp \
        --cleanup.remove-egs true \
        --use-gpu false \
        --dir=$exp_dir  \
        || exit 1;
    
    #   --egs.dir $master_egs_dir \
    
    # ### Print training info ###
    # cat_tasks=""
    # cat_typos=""
    # for i in `seq 0 $[$num_tasks-1]`; do
    #     cat_tasks="${cat_tasks}_${task_list[$i]}"
    #     cat_typos="${cat_typos}_${typo_list[$i]}"
    # done
    
    # # Get training ACC in right format for plotting
    # utils/format_accuracy_for_plot.sh "$main_dir/exp/nnet3/multitask/log" "ACC_nnet3_multitask${cat_tasks}${cat_typos}.txt";



    echo "### ============== ###"
    echo "### END TRAIN NNET ###"
    echo "### ============== ###"

fi




# if [ "$make_copies_nnet" -eq "1" ]; then

#     echo "### ========================== ###"
#     echo "### SPLIT & COPY NNET PER TASK ###"
#     echo "### ========================== ###"
    
#     for i in `seq 0 $[$num_tasks-1]`;do
#         task_dir=$exp_dir/${task_list[$i]}
        
#         mkdir -p $task_dir
        
#         echo "$0: rename output name for each task to 'output' and "
#         echo "add transition model."
        
#         nnet3-copy \
#             --edits="rename-node old-name=output-$i new-name=output" \
#             $exp_dir/final.raw \
#             - | \
#             nnet3-am-init \
#                 ${multi_ali_dirs[$i]}/final.mdl \
#                 - \
#                 $task_dir/final.mdl \
#             || exit 1;
        
#         cp $exp_dir/cmvn_opts $task_dir/cmvn_opts || exit 1;
        
#         echo "$0: compute average posterior and readjust priors for task ${task_list[$i]}."
        
#         steps/nnet3/adjust_priors.sh \
#             --cmd "$cmd" \
#             --use-gpu true \
#             --iter "final" \
#             --use-raw-nnet false \
#             $task_dir ${multi_egs_dirs[$i]} \
#             || exit 1;
#     done
# fi





# if [ "$decode_test" -eq "1" ]; then

#     echo "### ============== ###"
#     echo "### BEGIN DECODING ###"
#     echo "### ============== ###"

#     if [ "${typo_list[0]}" == "mono" ]; then
#         echo "Decoding with monophone graph, make sure you compiled"
#         echo "it with mkgraph.sh --mono (the flag is important!)"
#     fi
    
#     test_data_dir=data_${task_list[0]}/test
#     graph_dir=exp_${task_list[0]}/${typo_list[0]}phones/graph
#     decode_dir=${exp_dir}/decode
#     final_model=${exp_dir}/${task_list[0]}/final_adj.mdl
    
#     mkdir -p $decode_dir

#     unknown_phone="SPOKEN_NOISE"
#     silence_phone="SIL"

#     echo "### decoding with $( `nproc` ) jobs, unigram LM ###"
    
#     steps/nnet3/decode.sh \
#         --nj `nproc` \
#         --cmd $cmd \
#         --max-active 250 \
#         --min-active 100 \
#         $graph_dir \
#         $test_data_dir\
#         $decode_dir \
#         $final_model \
#         $unknown_phone \
#         $silence_phone \
#         | tee $decode_dir/decode.log

#     printf "\n#### BEGIN CALCULATE WER ####\n";

#     # Concatenate tasks to for WER filename
#     cat_tasks=""
#     cat_typos=""
#     for i in `seq 0 $[$num_tasks-1]`; do
#         cat_tasks="${cat_tasks}_${task_list[$i]}"
#         cat_typos="${cat_typos}_${typo_list[$i]}"
#     done
    
#     for x in ${decode_dir}*; do
#         [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh > WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     done


#     echo "hidden_dim=$hidden_dim"  >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     echo "num_epochs=$num_epochs"  >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     echo "task2weight=$task2weight" >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;

#     echo ""  >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;

#     echo "test_data_dir=$test_data_dir" >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     echo "graph_dir=$graph_dir" >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     echo "decode_dir=$decode_dir" >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     echo "final_model=$final_model" >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
    
    
#     for i in `seq 0 $[$num_tasks-1]`;do
        
#         num_targets=${num_targets_list[$i]}

#         num_targets=`tree-info ${multi_ali_dirs[$i]}/tree 2>/dev/null | grep num-pdfs | awk '{print $2}'` || exit 1;
        
#         echo "
#     ###### BEGIN TASK INFO ######
#     task= ${task_list[$i]}
#     num_targets= $num_targets
#     data_dir= ${multi_data_dirs[$i]}
#     ali_dir= ${multi_ali_dirs[$i]}
#     egs_dir= ${multi_egs_dirs[$i]}
#     ###### END TASK INFO ######
#     " >> WER_nnet3_multitask${cat_tasks}${cat_typos}.txt;
#     done

#     echo "###==============###"
#     echo "### END DECODING ###"
#     echo "###==============###"

# fi