#include "feat/mel-computations.h"
#include "matrix/kaldi-matrix.h"
#include "matrix/matrix-functions.h"
#include "util/common-utils.h"


namespace {

using namespace kaldi;

class FbankToMfccComputer {
 public:
  FbankToMfccComputer(int num_bins,
                      int num_ceps,
                      BaseFloat cepstral_lifter)
    : num_bins_(num_bins),
      num_ceps_(num_ceps), 
      cepstral_lifter_(cepstral_lifter),
      full_dct_matrix_(num_bins, num_bins),
      truncated_dct_matrix_(full_dct_matrix_.RowRange(0, num_ceps)),
      lifter_coeffs_(num_ceps)
  {
    ComputeDctMatrix(&full_dct_matrix_);
    // Now the `num_ceps` rows referenced by `truncated_dct_matrix_` are the ones corresponding to our MFCC features.

    if (cepstral_lifter_ != 0.0) {
      ComputeLifterCoeffs(cepstral_lifter_, &lifter_coeffs_);
    }
  }

  // Computes one set of MFCC features from a log-mel filterbank.
  // Note: Currently unused but serves as a reference.
  void Compute(const VectorBase<BaseFloat> &fbank,
               VectorBase<BaseFloat> *mfcc) const {
    KALDI_ASSERT(mfcc != nullptr);
    mfcc->SetZero();

    mfcc->AddMatVec(1.0, truncated_dct_matrix_, kNoTrans, fbank, 0.0);
    if (cepstral_lifter_ != 0.0) {
      mfcc->MulElements(lifter_coeffs_);
    }
  }

  // Computes a batch of MFCC features from log-mel filterbanks.
  // Note that since Kaldi uses the "rows as features" format,
  // the computations appear transposed comparing to the above.
  void Compute(const MatrixBase<BaseFloat> &fbanks,
               MatrixBase<BaseFloat> *mfccs) const {
    KALDI_ASSERT(mfccs != nullptr);
    mfccs->SetZero();

    mfccs->AddMatMat(1.0, fbanks, kNoTrans, truncated_dct_matrix_, kTrans, 0.0);
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

    po.Register("num-mel-bins", &num_bins,
		"Number of original triangular mel-frequency bins");
    po.Register("num-ceps", &num_ceps,
                "Number of cepstra in MFCC computation (including C0)");
    po.Register("cepstral-lifter", &cepstral_lifter,
                "Constant controlling scaling of MFCCs");

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

    FbankToMfccComputer computer(num_bins, num_ceps, cepstral_lifter);

    int32 num_utts = 0;
    for (; !kaldi_reader.Done(); kaldi_reader.Next(), num_utts++) {
      const std::string utt = kaldi_reader.Key();
      const Matrix<BaseFloat> &fbanks = kaldi_reader.Value();

      if (fbanks.NumCols() != num_bins) {
        KALDI_ERR << utt << ": got " << fbanks.NumCols() << " filterbanks"
                  << ", but --num-mel-bins is " << num_bins;
      }

      Matrix<BaseFloat> mfccs(fbanks.NumRows(), num_ceps);
      computer.Compute(fbanks, &mfccs);

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
