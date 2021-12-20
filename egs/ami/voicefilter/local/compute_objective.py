#!/usr/bin/env python3
# Computes the objective based on the neural network outputs and ground truth.
# hk3129: Authored by me.

import numpy as np
import argparse
import os

import tqdm

def generate_matrices(file_path):
  utt_id = None
  matrix = []
  with open(file_path, 'r') as f:
    for line in f:
      if '[' in line:
        utt_id = line.split()[0]
        matrix = []
      elif ']' in line:
        matrix.append([float(value) for value in line.strip().split()[0:-1]])
        yield utt_id, np.array(matrix)
      else:
        matrix.append([float(value) for value in line.strip().split()])

def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--predictions-dir', default='exp3/output', type=str)
  parser.add_argument('--ground-truth-dir', default='data/processed5/clean/test', type=str)

  cfg = parser.parse_args()

  predictions = generate_matrices(os.path.join(cfg.predictions_dir, 'feats_matrix'))
  ground_truth = generate_matrices(os.path.join(cfg.ground_truth_dir, 'feats_matrix'))

  output_dir = cfg.predictions_dir

  with open(os.path.join(output_dir, 'objective_report'), 'w') as f:
    f.write('utt_id\ttotal_mse\tmax_mse_per_frame\tmin_mse_per_frame\tmax_mse_per_feature\tmin_mse_per_feature\tmse_per_frame\tmse_per_feature\n')
    for ((utt_id_pred, matrix_pred), (utt_id_gt, matrix_gt)) in tqdm.tqdm(zip(predictions, ground_truth)):
      assert utt_id_pred == utt_id_gt
      squared_diff = np.square(matrix_pred - matrix_gt)
      mse_per_feature = squared_diff.mean(axis=0)
      mse_per_frame = squared_diff.mean(axis=1)
      mse = squared_diff.mean(axis=None)
      f.write(f'{utt_id_pred}\t{mse}\t{np.max(mse_per_frame)}\t{np.min(mse_per_frame)}\t \
        {np.max(mse_per_feature)}\t{np.min(mse_per_feature)}\n')


if __name__ == "__main__":
  main()
