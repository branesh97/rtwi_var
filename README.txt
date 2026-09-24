# Australian dollar drivers — initial estimation

This folder contains the **initial empirical analysis** for an ESSA *Short Supply* article on the Australian dollar:

> **What can the Australian dollar tell us about our economic environment?**

The purpose of this code is to examine how the relative importance of commodity prices, global risk, relative interest rates, domestic macroeconomic conditions and exchange-rate-specific shocks changes across horizons and historical episodes.

This folder should be treated as **article-stage analysis**, not as the final code base for a future journal paper. A later research project may use a richer information set and/or alternative identification strategies.

## Background

The modelling strategy builds on earlier work replicating:

> Manalo, J., Perera, D. and Rees, D. M. (2015), “Exchange Rate Movements and the Australian Economy”, *Economic Modelling*, 47, 53–62.

The replication exercise is kept separately and is **not duplicated here**:

https://github.com/branesh97/replication_manalo_perera_rees_2015

The present analysis differs from the replication exercise in its variables, sample, research question and use of both classical and Bayesian small-open-economy VARs.

---

## Folder structure

```text
initial_estimation/
│
├── _func/
│   ├── bootstrap_after_bootstrap_soe.m
│   ├── bvar_soe.m
│   ├── calculate_IRF_FEVD.m
│   ├── historical_decomposition.m
│   ├── olsvar_soe.m
│   └── olsvar.m
│
├── data/
│   └── data_collected.xlsx
│
├── figures/
│   └── generated figures
│
├── results/
│   └── generated .mat, .xlsx and .txt outputs
│
├── article_figure_1.m
├── descriptive.m
│
├── svar_initial.m
├── svar_bootstrap_pre_essa_article_version.m
├── svar_bootstrap.m
├── svar_ordering_robustness.m
├── svar_lag_robustness.m
├── svar_hd.m
├── svar_hd_order_robustness.m
├── svar_hd_final.m
├── svar_hd_final_diagnostic_recentsplit.m
├── svar_recent_quarter_hd.m
│
├── bvar_initial.m
├── bvar_baseline.m
├── bvar_irf_check.m
├── bvar_fevd_hd.m
├── bvar_fevd_hd_articlefig.m
├── bvar_lambda_subs_robustness.m
├── bvar_hd_final.m
├── bvar_hd_final_diagnostic_recentsplit.m
├── bvar_recent_quarter_hd.m
│
└── model_notes.qmd
```

The exact set of generated files in `figures/` and `results/` may change as the article is revised.

---

## Data

The main input file is:

```text
data/data_collected.xlsx
```

The estimation sample is:

```text
1995Q1–2026Q2
```

The baseline seven-variable system is ordered as:

1. US real GDP gap
2. RBA commodity price index
3. VIX
4. Australian real GDP gap
5. Australian trimmed-mean inflation
6. Australia–US two-year government-bond yield spread
7. Australian real trade-weighted index (RTWI)

Real GDP series are expressed as log deviations from a quadratic trend. Commodity prices, the VIX and the RTWI enter in log form scaled by 100. Trimmed-mean inflation and the two-year yield spread enter in their observed units.

The spreadsheet contains the underlying data used by the scripts. Source documentation should be retained with the spreadsheet whenever the dataset is updated.

---

## Baseline model

The baseline model is a quarterly VAR with **two lags** and a **small-open-economy block-exogeneity restriction**.

The first three variables form the foreign block. Their equations contain only lags of foreign variables. Domestic equations may depend on lags of all variables.

Structural shocks are identified recursively using the ordering above. The RTWI is ordered last, so the exchange-rate-specific structural shock is the component of the contemporaneous RTWI innovation not explained by the other shocks in the system.

The main article results focus on:

- RTWI forecast-error variance decompositions (FEVDs);
- historical decompositions (HDs);
- robustness across classical SVAR and Bayesian VAR specifications.

Impulse responses are mainly used as model-consistency and interpretation checks.

See `model_notes.qmd` for the model equations, identification assumptions and BVAR prior.

---

## Recommended run order

### 1. Descriptive analysis

```matlab
descriptive
```

Produces the descriptive plots, correlations and preliminary regressions used to motivate the structural analysis.

### 2. Baseline classical SOE-SVAR

```matlab
svar_initial
```

Estimates the baseline VAR(2), applies the small-open-economy restriction, constructs the recursive structural identification, and produces initial IRFs and FEVDs.

### 3. Classical SVAR uncertainty

```matlab
svar_bootstrap
```

Uses the two-stage bias-corrected residual bootstrap adapted to the small-open-economy restriction. The article version reports central 70% and 95% intervals.

### 4. Classical robustness checks

```matlab
svar_ordering_robustness
svar_lag_robustness
```

These assess sensitivity to recursive ordering and lag length.

### 5. Classical historical decomposition

```matlab
svar_hd
svar_hd_order_robustness
svar_hd_final
```

The diagnostic recent-period split is in:

```matlab
svar_hd_final_diagnostic_recentsplit
```

and the quarter-specific recent decomposition is in:

```matlab
svar_recent_quarter_hd
```

### 6. Initial BVAR calibration

```matlab
bvar_initial
```

Used to inspect the Minnesota prior, persistence and the effect of the SOE restrictions.

### 7. Final stable SOE-BVAR

```matlab
bvar_baseline
```

The preferred BVAR specification uses:

- VAR lag order: `p = 2`
- Minnesota tightness: `lambda = 0.20`
- lag-decay exponent: `1`
- explicit own-first-lag prior means:
  ```text
  [0, 1, 0, 0, 0, 0, 1]'
  ```
- 5,000 burn-in iterations
- 10,000 retained posterior draws
- posterior conditioned on stability
- maximum permitted companion root below `0.9999`

The stability restriction is imposed by rejecting coefficient draws outside the stable region.

### 8. BVAR IRF consistency check

```matlab
bvar_irf_check
```

Compares BVAR RTWI responses with the classical SVAR for:

- a +10 log-point commodity-price shock;
- a +10 log-point VIX shock;
- a +100 basis point AU–US two-year spread shock.

### 9. BVAR FEVD and historical decomposition

```matlab
bvar_fevd_hd
```

The article-specific figures are produced by:

```matlab
bvar_fevd_hd_articlefig
```

This script produces the posterior FEVDs and the selected-episode historical-decomposition chart used in the ESSA article.

### 10. BVAR robustness

```matlab
bvar_lambda_subs_robustness
```

Checks sensitivity to Minnesota tightness values of `0.10`, `0.20` and `0.30`.

The recent-period diagnostic split is in:

```matlab
bvar_hd_final_diagnostic_recentsplit
```

and the quarter-specific recent decomposition is in:

```matlab
bvar_recent_quarter_hd
```

---

## Article figures

The three principal article figures are generated from:

```text
article_figure_1.m
bvar_fevd_hd_articlefig.m
```

The intended article outputs are:

1. **Figure 1** — the Australian real TWI through changing economic environments;
2. **Figure 2** — RTWI FEVD across forecast horizons;
3. **Figure 3** — historical contributions to selected Australian-dollar episodes.

The SVG versions in `figures/` are the preferred versions for page layout because they are vector graphics.

---

## Historical decomposition convention

The historical decomposition separates the RTWI into:

- baseline dynamics (constant and initial conditions);
- global activity shocks;
- commodity-price shocks;
- global-risk / VIX shocks;
- domestic macro shocks;
- relative-yield shocks;
- other exchange-rate shocks.

For presentation, Australian GDP and inflation shocks are grouped as **domestic macro**.

The stacked BVAR episode chart is based on the **posterior-mean parameter model** so that the historical accounting identity is exact. Posterior medians and credible intervals are calculated separately from the posterior draws.

“Other exchange-rate shocks” should **not** be interpreted as a single economic cause. It is the exchange-rate innovation left after conditioning on the variables and recursive identification used in this model.

---

## Reproducibility notes

- Run scripts from the `initial_estimation/` folder.
- Helper functions are added from `_func/`.
- Scripts expect `data/data_collected.xlsx` to retain its current variable names.
- `figures/` and `results/` are output folders and some files may be overwritten when scripts are rerun.
- Random-number seeds are set within the BVAR routines for reproducibility.
- The final BVAR stores residual draws because the posterior historical decomposition requires them.
- The code was developed for MATLAB. The precise MATLAB release has not been pinned; this should be recorded before a permanent research archive is created.

---

## Scope and limitations

This code is designed to support a short, magazine-style ESSA article. The model is deliberately parsimonious.

In particular:

- the foreign activity block uses US real GDP rather than a broad trading-partner activity measure;
- relative yields are represented by the Australia–US two-year government-bond yield spread;
- the VIX is used as the principal global financial-risk measure;
- China-specific variables, broad-US-dollar factors, portfolio flows, currency hedging and multi-country yield differentials are not separately identified.

These omissions are especially relevant when interpreting the sizeable “other exchange-rate shock” contribution to the late-sample appreciation. A future journal-oriented project may expand the information set and use alternative identification approaches.

---

## Key reference

Manalo, J., Perera, D. and Rees, D. M. (2015), “Exchange Rate Movements and the Australian Economy”, *Economic Modelling*, 47, 53–62.

Replication repository:

https://github.com/branesh97/replication_manalo_perera_rees_2015
