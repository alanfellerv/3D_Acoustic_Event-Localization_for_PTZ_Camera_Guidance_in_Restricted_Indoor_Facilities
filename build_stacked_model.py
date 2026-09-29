"""
build_stacked_model.py
-----------------------
Combines the tuned SVM and Random Forest classifiers into a single
StackingClassifier, using a logistic regression meta-learner trained
on both models' outputs via internal cross-validation.

Requires: dataset.csv (with TX_TDOA, TY_TDOA, Diagonal_TDOA_1/2,
MUSIC_Az, GCC_Az, ILD_dB, RMS_mean, FFT_PeakFreq, SpecEntropyNorm,
AzSector columns) in the same directory.
"""

import numpy as np
import pandas as pd
import joblib

from sklearn.model_selection import train_test_split, StratifiedKFold
from sklearn.ensemble import StackingClassifier, RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.svm import SVC
from sklearn.preprocessing import StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix

RANDOM_STATE = 42
TEST_SIZE = 0.25
TARGET_COLUMN = "AzSector"
FEATURE_COLUMNS = [
    "TX_TDOA", "TY_TDOA", "Diagonal_TDOA_1", "Diagonal_TDOA_2",
    "MUSIC_Az", "GCC_Az", "ILD_dB", "RMS_mean", "FFT_PeakFreq", "SpecEntropyNorm",
]


def parse_numeric(value):
    """Handles MATLAB-exported complex-valued ILD_dB/RMS_mean strings
    (a known artifact of squaring complex baseband signals upstream) by
    taking their magnitude. Real-valued strings pass through unchanged."""
    s = str(value).strip()
    if "i" in s or "j" in s:
        try:
            return abs(complex(s.replace("i", "j")))
        except ValueError:
            return np.nan
    try:
        return float(s)
    except ValueError:
        return np.nan


def load_dataset(path):
    df = pd.read_csv(path)
    for col in ["ILD_dB", "RMS_mean"]:
        df[col] = df[col].apply(parse_numeric)
    df = df.dropna(subset=FEATURE_COLUMNS + [TARGET_COLUMN]).reset_index(drop=True)
    X = df[FEATURE_COLUMNS].to_numpy(dtype=float)
    y = df[TARGET_COLUMN].astype(str).to_numpy()
    return X, y


X, y = load_dataset("dataset.csv")
class_names = sorted(pd.unique(y).tolist(),
                      key=lambda s: float(s.replace("Az_", "").split("to")[0]))

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=TEST_SIZE, random_state=RANDOM_STATE, stratify=y
)
cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=RANDOM_STATE)

# Base learners, using the same tuned hyperparameters found earlier.
# probability=True is required so soft-voting/stacking can use SVM's
# predicted probabilities, not just hard labels.
svm_base = Pipeline([
    ("scaler", StandardScaler()),
    ("svc", SVC(C=100, kernel="linear", probability=True, random_state=RANDOM_STATE)),
])
rf_base = RandomForestClassifier(
    n_estimators=100, max_depth=None, max_features="sqrt",
    min_samples_leaf=1, random_state=RANDOM_STATE, n_jobs=-1,
)

stacked_model = StackingClassifier(
    estimators=[("svm", svm_base), ("rf", rf_base)],
    final_estimator=LogisticRegression(max_iter=2000),
    cv=cv,
)
stacked_model.fit(X_train, y_train)

y_pred = stacked_model.predict(X_test)
acc = accuracy_score(y_test, y_pred)
print(f"Stacked model held-out test accuracy: {acc:.4f}")
print()
print(classification_report(y_test, y_pred, labels=class_names, zero_division=0))

joblib.dump(stacked_model, "stacked_model.joblib")
print("Saved stacked_model.joblib")
