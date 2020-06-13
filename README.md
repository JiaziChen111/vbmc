# Variational Bayesian Monte Carlo (VBMC) - v0.96 (beta)

**News:** 
- **Major update** VBMC v1.0 is about to be released! This update will include full support for noisy log-likelihood evaluations, a linear transformation of the inference space to better represent the variational posterior, and a number of tweaks to the algorithm's settings for improved performance.

## What is it

> *What if there was a model-fitting method similar to Bayesian optimization (e.g., [BADS](https://github.com/lacerbi/bads)), which, instead of returning just the optimal parameter vector, would also return its uncertainty (even better, the full posterior distribution of the parameters), and maybe even a metric than can be used for Bayesian model comparison?*

VBMC is an approximate inference method designed to fit and evaluate computational models with a limited budget of likelihood evaluations (e.g., for computationally expensive models). Specifically, VBMC simultaneously computes:
- an approximate posterior distribution of the model parameters; 
- an approximation — technically, an approximate lower bound — of the log model evidence (also known as log marginal likelihood or log Bayes factor), a metric used for [Bayesian model selection](https://en.wikipedia.org/wiki/Bayes_factor).

Extensive benchmarks on both artificial test problems and a large number of real model-fitting problems from computational and cognitive neuroscience show that, with the exception of the easiest cases, VBMC vastly outperforms existing inference methods for expensive models [[1, 2](#references)].

VBMC runs with virtually no tuning and it is very easy to set up for your problem (especially if you are already familiar with [BADS](https://github.com/lacerbi/bads), our model-fitting algorithm based on Bayesian optimization).

### Should I use VBMC?

VBMC is effective when:

- the model log-likelihood function is a black-box (e.g., the gradient is unavailable);
- the likelihood is at least moderately expensive to compute (say, half a second or more per evaluation);
- the model has up to `D = 10` continuous parameters (maybe a few more, but no more than `D = 20`);
- the target posterior distribution is continuous and reasonably smooth (see [here](https://github.com/lacerbi/vbmc/wiki#general));
- optionally, log-likelihood evaluations may be noisy (e.g., estimated via simulation).

Conversely, if your model can be written analytically, you should exploit the powerful machinery of probabilistic programming frameworks such as [Stan](http://mc-stan.org/) or [PyMC3](https://docs.pymc.io/).

## Installation

[**Download the latest version of VBMC as a ZIP file**](https://github.com/lacerbi/vbmc/archive/master.zip).
- To install VBMC, clone or unpack the zipped repository where you want it and run the script `install.m`.
   - This will add the VBMC base folder to the MATLAB search path.
- To see if everything works, run `vbmc('test')`.

## Quick start

The VBMC interface is similar to that of MATLAB optimizers. The basic usage is:

```matlab
[VP,ELBO,ELBO_SD] = vbmc(FUN,X0,LB,UB,PLB,PUB);
```
with input parameters:
- `FUN`, a function handle to the log posterior distribution of your model (that is, log prior plus log likelihood of a dataset and model, for a given input parameter vector);
- `X0`, the starting point of the inference (a row vector);
- `LB` and `UB`, hard lower and upper bounds for the parameters;
- `PLB` and `PUB`, *plausible* lower and upper bounds, that is a box that ideally brackets a region of high posterior density.

The output parameters are:
- `VP`, a struct with the variational posterior approximating the true posterior;
- `ELBO`, the (estimated) lower bound on the log model evidence;
- `ELBO_SD`, the standard deviation of the estimate of the `ELBO` (*not* the error between the `ELBO` and the true log model evidence, which is generally unknown).

The variational posterior `vp` can be manipulated with functions such as `vbmc_moments` (compute posterior mean and covariance), `vbmc_pdf` (evaluates the posterior density), `vbmc_rnd` (draw random samples), `vbmc_kldiv` (Kullback-Leibler divergence between two posteriors), `vbmc_mtv` (marginal total variation distance between two posteriors); see also [this question](https://github.com/lacerbi/vbmc/wiki#what-is-vp-and-what-do-i-do-with-it).

### Next steps

- For a tutorial with many extensive usage examples, see [**vbmc_examples.m**](https://github.com/lacerbi/vbmc/blob/master/vbmc_examples.m). You can also type `help vbmc` to display the documentation.

- For practical recommendations, such as how to set `LB` and `UB` and the plausible bounds, and any other question, check out the FAQ on the [VBMC wiki](https://github.com/lacerbi/vbmc/wiki).

- If you want to run VBMC on a noisy or stochastic log-likelihood, see [below](#vbmc-with-noisy-likelihoods).

### For BADS users

If you already use [Bayesian Adaptive Direct Search (BADS)](https://github.com/lacerbi/bads) to fit your models, setting up VBMC on your problem should be particularly simple; see [here](https://github.com/lacerbi/vbmc/wiki#i-already-run-bads-on-my-problem-how-do-i-run-vbmc).

## How does it work

VBMC combines two machine learning techniques in a novel way: 
- [variational inference](https://en.wikipedia.org/wiki/Variational_Bayesian_methods), a method to perform approximate Bayesian inference;
- Bayesian quadrature, a technique to estimate the value of expensive integrals.

VBMC iteratively builds an approximation of the true, expensive target posterior via a [Gaussian process](https://en.wikipedia.org/wiki/Gaussian_process) (GP), and it matches a variational distribution — an expressive mixture of Gaussians — to the GP. 

This matching process entails optimization of the *expected lower bound* (ELBO), that is a lower bound on the log marginal likelihood (LML), also known as log model evidence. Crucially, we estimate the ELBO via Bayesian quadrature, which is fast and does not require further evaluation of the true target posterior.

In each iteration, VBMC uses *active sampling* to select which points to evaluate next in order to explore the posterior landscape and reduce uncertainty in the approximation.

![VBMC demo](https://github.com/lacerbi/vbmc/blob/master/docs/vbmc-demo.gif "Fig 1: VBMC demo")

In the figure above, we show an example VBMC run on a "banana" function. The left panel shows the ground truth for the target posterior density. In the middle panel we show VBMC at work (contour plots of the variational posterior) across iterations. Red crosses are the centers of the mixture of Gaussians used as variational posterior, whereas dots are sampled points in the training set (*black*: previously sampled points, *blue*: points sampled in the current iteration). The right panel shows a plot of the estimated ELBO vs. the true log marginal likelihood (LML).

In the figure below, we show another example VBMC run on a "lumpy" distribution.

![Another VBMC demo](https://github.com/lacerbi/vbmc/blob/master/docs/vbmc-demo-2.gif "Fig 2: Another VBMC demo")

See the VBMC paper for more details [[1](#references)].

## VBMC with noisy likelihoods

About to appear — stay tuned!

## Troubleshooting

The VBMC toolbox is under active development. The toolbox has been extensively tested in several benchmarks and published papers, but as with any approximate inference technique you need to double-check your results. See the FAQ for more information on [diagnostics](https://github.com/lacerbi/vbmc/wiki#troubleshooting).

If you have trouble doing something with VBMC, spot bugs or strange behavior, or you simply have some questions, please contact me at <luigi.acerbi@gmail.com>, putting 'VBMC' in the subject of the email.

## VBMC for other programming languages

VBMC is currently available only for MATLAB. A Python version is being planned, ideally before the [great filter](https://en.wikipedia.org/wiki/Great_Filter).

If you are interested in porting VBMC to Python or another language (R, [Julia](https://julialang.org/)), please get in touch at <luigi.acerbi@gmail.com> (putting  'VBMC' in the subject of the email); I'd be willing to help.
However, before contacting me for this reason, please have a good look at the codebase here on GitHub, and at the paper [[1](#references)]. VBMC is a fairly complex piece of software, so be aware that porting it will require considerable effort and programming/computing skills.

## References

1. Acerbi, L. (2018). Variational Bayesian Monte Carlo. In *Advances in Neural Information Processing Systems 31*: 8222-8232. ([paper + supplement on arXiv](https://arxiv.org/abs/1810.05558), [NeurIPS Proceedings](https://papers.nips.cc/paper/8043-variational-bayesian-monte-carlo))
2. Acerbi, L. (2019). An Exploration of Acquisition and Mean Functions in Variational Bayesian Monte Carlo. In *Proc. Machine Learning Research* 96: 1-10. 1st Symposium on Advances in Approximate Bayesian Inference, Montréal, Canada. ([paper in PMLR](http://proceedings.mlr.press/v96/acerbi19a.html))

You can cite VBMC in your work with something along the lines of

> We estimated approximate posterior distibutions and approximate lower bounds to the model evidence of our models using Variational Bayesian Monte Carlo (VBMC; Acerbi, 2018, 2019). VBMC combines variational inference and active-sampling Bayesian quadrature to perform approximate Bayesian inference in a sample-efficient manner.

Besides formal citations, you can demonstrate your appreciation for VBMC in the following ways:

- *Star* the VBMC repository on GitHub;
- [Follow me on Twitter](https://twitter.com/AcerbiLuigi) for updates about VBMC and other projects I am involved with;
- Tell me about your model-fitting problem and your experience with VBMC (positive or negative) at <luigi.acerbi@gmail.com> (putting  'VBMC' in the subject of the email).

You may also want to check out [Bayesian Adaptive Direct Search](https://github.com/lacerbi/bads) (BADS), our method for fast Bayesian optimization.

### License

VBMC is released under the terms of the [GNU General Public License v3.0](https://github.com/lacerbi/vbmc/blob/master/LICENSE.txt).
