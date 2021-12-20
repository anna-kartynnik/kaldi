// Credit: Ted Yin (https://gist.github.com/Determinant/089076dd87fa820f57ea)
// Appends speaker embeddings to a feature matrix using utterance-to-speaker mapping.

#include "base/kaldi-common.h"
#include "util/table-types.h"
#include "util/parse-options.h"
#include <map>

using namespace kaldi;
const char *usage =
    "Concatenate features with speaker level xvector (e.g. appending speaker\n"
    "xvector to each frame of the corresponding utterance)\n"
    "Usage: append-xvectors <xvector-rspecifier> <utt2spk-rspecifier> <in-rspecifier2> <out-wspecifier>\n\n"
    "e.g.: append-xvectors 'ark:copy-vector scp:spk_xvector.scp ark:- |' "
    "ark:aurora4/s5/data/train_si84_clean/utt2spk 'ark:copy-feats scp:t.scp ark:- |' 'ark,t:-'\n";

typedef std::map<std::string, std::string> StringToString_t;
typedef std::map<std::string, Vector<BaseFloat> > StringToVector_t;
StringToString_t utt2spkr;
StringToVector_t spkr_xvectors;

int main(int argc, char *argv[]) {
    try {
        ParseOptions po(usage);
        po.Read(argc, argv);
        if (po.NumArgs() != 4)
        {
            po.PrintUsage();
            exit(1);
        }
        std::string spkr_xvector_rspecifier = po.GetArg(1),
                    utt2spkr_rspecifier = po.GetArg(2),
                    feature_rspecifier = po.GetArg(3),
                    feature_wspecifier = po.GetArg(4);

        SequentialBaseFloatVectorReader spkr_xvector_reader = SequentialBaseFloatVectorReader(spkr_xvector_rspecifier);
        SequentialTokenVectorReader utt2spkr_reader = SequentialTokenVectorReader(utt2spkr_rspecifier);
        SequentialBaseFloatMatrixReader feature_reader = SequentialBaseFloatMatrixReader(feature_rspecifier);
        BaseFloatMatrixWriter feature_writer = BaseFloatMatrixWriter(feature_wspecifier);

        for (; !spkr_xvector_reader.Done(); spkr_xvector_reader.Next())
        {
            fprintf(stderr, "read xvector for spkr: %s\n", spkr_xvector_reader.Key().c_str());
            spkr_xvectors[spkr_xvector_reader.Key()] = spkr_xvector_reader.Value();
        }
        for (; !utt2spkr_reader.Done(); utt2spkr_reader.Next())
        {
            const std::vector<std::string> spkr = utt2spkr_reader.Value();
            assert(spkr.size() >= 1);
            fprintf(stderr, "%s => %s\n", utt2spkr_reader.Key().c_str(), (*spkr.begin()).c_str());
            utt2spkr[utt2spkr_reader.Key()] = *spkr.begin();
        }

        for (; !feature_reader.Done(); feature_reader.Next())
        {
            const std::string &utter = feature_reader.Key();
            StringToString_t::iterator it = utt2spkr.find(utter);
            if (it == utt2spkr.end())
            {
                fprintf(stderr, "spkr for %s not found\n", utter.c_str());
                exit(-1);
            }
            StringToVector_t::iterator it2 = spkr_xvectors.find(it->second);
            if (it2 == spkr_xvectors.end())
            {
                fprintf(stderr, "xvector for spkr %s not found\n", it->second.c_str());
                exit(-1);
            }
            const Vector<BaseFloat> &xvector = it2->second;
            const Matrix<BaseFloat> &feat = feature_reader.Value();
            int n = feat.NumRows();
            int m = feat.NumCols();
            int im = xvector.Dim();
            Matrix<BaseFloat> appended(n, m + im);
            for (int i = 0; i < n; i++)
            {
                memmove(appended.RowData(i), feat.RowData(i), sizeof(BaseFloat) * m);
                memmove(appended.RowData(i) + m, xvector.Data(), sizeof(BaseFloat) * im);
            }
            feature_writer.Write(utter, appended);
        }
    }
    catch (const std::exception &e)
    {
        std::cerr << e.what();
        return -1;
    }
    return 0;
}
