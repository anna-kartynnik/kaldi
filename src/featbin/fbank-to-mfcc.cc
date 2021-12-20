// Author: Hanna Kartynnik (hk3129) [implemented from scratch].
// Computes MFCC features provided (log-)mel filterbanks.

#include "feat/mel-computations.h"
#include "matrix/kaldi-matrix.h"
#include "matrix/matrix-functions.h"
#include "util/common-utils.h"


namespace {

using namespace kaldi;

class LogFbankToMfccComputer {
 public:
  // Arguments:
  //   num_bins: The number of mel filter bank bins.
  //   num_ceps: The number of MFCCs. Should be at most `num_bins`.
  //   cepstral_lifter: Scaling factor applied to cepstra (claimed to be used for HTK compatibility).
  LogFbankToMfccComputer(int num_bins,
                         int num_ceps,
                         BaseFloat cepstral_lifter)
    : num_bins_(num_bins),
      num_ceps_(num_ceps), 
      cepstral_lifter_(cepstral_lifter),
      full_dct_matrix_(num_bins, num_bins),
      truncated_dct_matrix_(full_dct_matrix_.RowRange(0, num_ceps)),
      lifter_coeffs_(num_ceps)
  {
    KALDI_ASSERT(num_ceps <= num_bins);

    // Compute the square discrete cosine transform matrix.
    ComputeDctMatrix(&full_dct_matrix_);
    // Now the `num_ceps` rows referenced by `truncated_dct_matrix_` (see the initializer list)
    // are the ones corresponding to our MFCC features.

    if (cepstral_lifter_ != 0.0) {
      ComputeLifterCoeffs(cepstral_lifter_, &lifter_coeffs_);
    }
  }

  // Computes one set of MFCC features from a log-mel filterbank.
  // Note: Currently unused but serves as a reference.
  void Compute(const VectorBase<BaseFloat> &log_fbank,
               VectorBase<BaseFloat> *mfcc) const {
    KALDI_ASSERT(mfcc != nullptr);
    mfcc->SetZero();

    // Apply the DCT by multiplying with the corresponding matrix.
    mfcc->AddMatVec(1.0, truncated_dct_matrix_, kNoTrans, log_fbank, 0.0);

    if (cepstral_lifter_ != 0.0) {
      mfcc->MulElements(lifter_coeffs_);
    }
  }

  // Computes a batch of MFCC features from log-mel filterbanks.
  // Note that since Kaldi uses the "rows as features" format,
  // the computations appear transposed comparing to the above.
  void Compute(const MatrixBase<BaseFloat> &log_fbanks,
               MatrixBase<BaseFloat> *mfccs) const {
    KALDI_ASSERT(mfccs != nullptr);
    mfccs->SetZero();

    // Batch transform via a matrix-matrix multiplication.
    mfccs->AddMatMat(1.0, log_fbanks, kNoTrans, truncated_dct_matrix_, kTrans, 0.0);

    if (cepstral_lifter_ != 0.0) {
      mfccs->MulColsVec(lifter_coeffs_);
    }
  }

 private:
  const int32 num_bins_;
  const int32 num_ceps_;
  const BaseFloat cepstral_lifter_;

  Matrix<BaseFloat> full_dct_matrix_;
  const SubMatrix<BaseFloat> truncated_dct_matrix_;

  Vector<BaseFloat> lifter_coeffs_;
};

}  // namespace


int main(int argc, char* argv[]) {
  try {
    const char *usage =
      "Computes MFCC features from the given log-mel filterbanks via a discrete cosine transform.\n"
      "Requires that the filterbanks have been generated with the default options.\n"
      "Usage: fbank-to-mfcc [options...] <fbanks-rspecifier> <mfcc-wspecifier>\n";

    ParseOptions po(usage);

    int32 num_bins = 23;
    int32 num_ceps = 13;
    BaseFloat cepstral_lifter = 22.0;
    bool use_log_fbank = true;

    po.Register("num-mel-bins", &num_bins,
		"Number of original triangular mel-frequency bins");
    po.Register("num-ceps", &num_ceps,
                "Number of cepstra in MFCC computation (including C0)");
    po.Register("cepstral-lifter", &cepstral_lifter,
                "Constant controlling scaling of MFCCs");
    po.Register("use-log-fbank", &use_log_fbank,
		"The input filter banks are logarithmic (the default; otherwise linear)");

    po.Read(argc, argv);

    if (po.NumArgs() != 2) {
      po.PrintUsage();
      exit(1);
    }

    std::string input_rspecifier = po.GetArg(1);
    std::string output_wspecifier = po.GetArg(2);

    SequentialBaseFloatMatrixReader kaldi_reader(input_rspecifier);

    BaseFloatMatrixWriter kaldi_writer(output_wspecifier);
    if (!kaldi_writer.Open(output_wspecifier)) {
      KALDI_ERR << "Could not initialize output with wspecifier " << output_wspecifier;
    }

    LogFbankToMfccComputer computer(num_bins, num_ceps, cepstral_lifter);

    int32 num_utts = 0;
    for (; !kaldi_reader.Done(); kaldi_reader.Next(), num_utts++) {
      const std::string utt = kaldi_reader.Key();
      Matrix<BaseFloat> inputs(kaldi_reader.Value());

      if (!use_log_fbank) {
	// Avoid taking the logarithm of zero.
	inputs.ApplyFloor(std::numeric_limits<float>::epsilon());
	inputs.ApplyLog();
      }
      const Matrix<BaseFloat> &log_fbanks = inputs;

      if (inputs.NumCols() != num_bins) {
        KALDI_ERR << utt << ": got " << inputs.NumCols() << " filterbanks"
                  << ", but --num-mel-bins is " << num_bins;
      }

      Matrix<BaseFloat> mfccs(log_fbanks.NumRows(), num_ceps);
      computer.Compute(log_fbanks, &mfccs);

      kaldi_writer.Write(utt, mfccs);

      if (num_utts % 10 == 0) {
        KALDI_LOG << "Processed " << num_utts << " utterances";
      }
      KALDI_VLOG(2) << "Processed features for key " << utt;
    }
    KALDI_LOG << " Done " << num_utts << " utterances.";
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
