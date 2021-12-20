# Training plot generator for nnet3.
# Author: Hanna Kartynnik (hk3129).
import argparse
import sys

import matplotlib.pyplot as plt

sys.path.insert(0, 'steps')
import libs.nnet3.report.log_parse as nnet3_log_parse


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument('--exp-dir', default='exp4', type=str)
  parser.add_argument('--start-iteration', default=0, type=int)
  parser.add_argument('--end-iteration', default=-1, type=int)
  parser.add_argument('--iteration-jump', default=1, type=int)

  cfg = parser.parse_args()

  [report, times, data] = nnet3_log_parse.generate_acc_logprob_report(cfg.exp_dir, key='objective')

  report_file_name = "{dir}/{key}.{output_name}.report.{iterations}".format(
    dir=cfg.exp_dir,
    key="objective",
    output_name="output",
    iterations=len(data)
  )

  start = cfg.start_iteration
  end = len(data) if cfg.end_iteration == -1 else cfg.end_iteration
  report_iterations = data[start:end:cfg.iteration_jump]

  with open(report_file_name, "w") as f:
    f.write(report)

  fig, ax = plt.subplots(figsize=(12, 6))
  x = [elem[0] for elem in report_iterations]
  ax.plot(x, [-elem[1] for elem in report_iterations], color='tab:blue', label='Training error')
  ax.plot(x, [-elem[2] for elem in report_iterations], color='tab:orange', label='Validation error')

  ax.set_title('Training progress')

  plt.xlabel('Iterations')
  plt.ylabel('MSE')

  ax.legend()

  plt.savefig(f'{cfg.exp_dir}_obj_report_{start}_{end}_{cfg.iteration_jump}.png')


if __name__ == "__main__":
  main()
