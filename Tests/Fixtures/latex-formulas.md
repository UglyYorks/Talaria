Here's a collection of LaTeX formulas across math and physics:

**Algebra & Calculus**

- Quadratic formula: `x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}`
- Fundamental theorem: `\int_a^b f'(x)\,dx = f(b) - f(a)`
- Chain rule: `\frac{dz}{dx} = \frac{\partial z}{\partial y} \cdot \frac{dy}{dx}`
- Taylor series: `f(x) = \sum_{n=0}^{\infty} \frac{f^{(n)}(a)}{n!}(x-a)^n`
- Integration by parts: `\int u\,dv = uv - \int v\,du`

**Sums, Limits, Products**

- Geometric series: `\sum_{n=0}^{\infty} ar^n = \frac{a}{1-r}, \quad |r| < 1`
- Euler's limit: `e = \lim_{n \to \infty} \left(1 + \frac{1}{n}\right)^n`
- Stirling: `n! \sim \sqrt{2\pi n}\left(\frac{n}{e}\right)^n`

**Linear Algebra**

- Matrix product: `(AB)_{ij} = \sum_{k=1}^{n} A_{ik}B_{kj}`
- Eigendecomposition: `A\mathbf{v} = \lambda\mathbf{v}`
- Determinant: `\det(A) = \sum_{\sigma \in S_n} \operatorname{sgn}(\sigma) \prod_{i=1}^{n} A_{i,\sigma(i)}`

**Probability & Statistics**

- Bayes' theorem: `P(A \mid B) = \frac{P(B \mid A)\,P(A)}{P(B)}`
- Normal density: `f(x) = \frac{1}{\sigma\sqrt{2\pi}} e^{-\frac{(x-\mu)^2}{2\sigma^2}}`
- Expectation: `\mathbb{E}[X] = \int_{-\infty}^{\infty} x\,f(x)\,dx`
- Binomial coefficient: `\binom{n}{k} = \frac{n!}{k!(n-k)!}`

**Physics**

- Mass–energy: `E = mc^2`
- Schrödinger equation: `i\hbar\frac{\partial}{\partial t}\Psi(\mathbf{r},t) = \hat{H}\Psi(\mathbf{r},t)`
- Maxwell: `\nabla \cdot \mathbf{E} = \frac{\rho}{\varepsilon_0}, \quad \nabla \times \mathbf{B} = \mu_0\mathbf{J} + \mu_0\varepsilon_0\frac{\partial \mathbf{E}}{\partial t}`
- Einstein field equations: `G_{\mu\nu} + \Lambda g_{\mu\nu} = \frac{8\pi G}{c^4} T_{\mu\nu}`
- Entropy: `S = -k_B \sum_i p_i \ln p_i`

**Famous Identities**

- Euler's identity: `e^{i\pi} + 1 = 0`
- Navier–Stokes: `\rho\left(\frac{\partial \mathbf{u}}{\partial t} + \mathbf{u}\cdot\nabla\mathbf{u}\right) = -\nabla p + \mu\nabla^2\mathbf{u} + \mathbf{f}`
- Fourier transform: `\hat{f}(\xi) = \int_{-\infty}^{\infty} f(x)e^{-2\pi i x\xi}\,dx`
- Riemann zeta: `\zeta(s) = \sum_{n=1}^{\infty} \frac{1}{n^s} = \prod_{p \text{ prime}} \frac{1}{1-p^{-s}}`

Want them in a compilable document, a specific field (ML, QM, GR), or display-math blocks with `\begin{equation}`?
