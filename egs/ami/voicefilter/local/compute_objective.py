#!/usr/bin/env python3

import numpy as np
import argparse
import os

def build_matrices(file_path):
  matrices_dict = {}

  utt_id = None
  matrix_str = ''
  with open(file_path, 'r') as f:
    lines = f.readlines()
    print(len(lines))
    for line in lines:
      if '[' in line:
        utt_id = line.split()[0]
        matrix_str = ''
      elif ']' in line:
        matrix_str += ','.join(line.strip().split()[0:-1])
        matrices_dict[utt_id] = np.matrix(matrix_str)
      else:
        matrix_str += ','.join(line.strip().split())
        matrix_str += ';'
    print(len(matrices_dict.keys()))

  return matrices_dict

def main():
 
  parser = argparse.ArgumentParser()
  parser.add_argument('--predictions-dir', default='exp3/output', type=str)
  parser.add_argument('--ground-truth-dir', default='data/processed5/clean/test', type=str)

  cfg = parser.parse_args()

  predictions = build_matrices(os.path.join(cfg.predictions_dir, 'feats_matrix'))
  ground_truth = build_matrices(os.path.join(cfg.ground_truth_dir, 'feats_matrix'))

  output_dir = cfg.predictions_dir

  with open(os.path.join(output_dir, 'objective_report'), 'w') as f:
    f.write('utt_id\ttotal_mse\tmax_mse_per_frame\tmin_mse_per_frame\tmax_mse_per_feature\tmin_mse_per_feature\tmse_per_frame\tmse_per_feature\n')
    for utt_id, matrix in predictions.items():
      mse_per_feature = (np.square(matrix - ground_truth[utt_id])).mean(axis=0)
      mse_per_frame = (np.square(matrix - ground_truth[utt_id])).mean(axis=1)
      #print(mse_per_frame.shape)
      mse = (np.square(matrix - ground_truth[utt_id])).mean(axis=None)
      f.write(f'{utt_id}\t{mse}\t{np.max(mse_per_frame)}\t{np.min(mse_per_frame)}\t \
        {np.max(mse_per_feature)}\t{np.min(mse_per_feature)}\n')
        #{mse_per_frame.flatten().tolist()}\t \
        #{mse_per_feature.flatten().tolist()\n}


if __name__ == "__main__":
  main()