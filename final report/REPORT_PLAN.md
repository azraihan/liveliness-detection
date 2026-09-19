# Final Capstone Report Draft Plan

## 1. Recommended report identity

### Working title

**Leveraging Temporal Information for Robust Liveness Verification**

This is the current title of `Temporal_Deepfake_Detection_for_Secure_Liveness_Verification.pdf` and should remain the working title for now. It reflects the broader project better than a title centered on the later specialist-routing experiment.

Use **liveness**, not *liveliness*, throughout the report. The repository name may remain unchanged, but the technical term in the report should be consistent.

### Central thesis

The report should tell one coherent engineering story:

1. Selfie-based financial identity verification must handle both physical presentation attacks and digitally manipulated faces.
2. The initial engineering response was a layered mobile--server--review architecture: a lightweight temporal MobileNetV3 first stage produces an on-device score; samples that are uncertain or policy-defined as high risk may be escalated to stronger server-side analysis; unresolved cases may eventually enter a human-review path. Only the local Flutter stage is integrated today, so server routing and human review must remain clearly labeled as target design.
3. The research then concentrated on temporal reasoning through G2V2Former and on domain generalization through GD-FAS, using LCC-FASD, Celeb-DF-v2, and Asian-Fakes to study transfer across attack families and populations.
4. Those experiments showed that strong presentation-attack performance does not automatically transfer to digitally generated deepfakes, and that direct deepfake fine-tuning improves one target domain while introducing retention and generalization trade-offs.
5. Embedding-conditioned specialist routing is a later, promising experiment within this broader investigation. The current repository's routed specialists outperform a universal Xception on an in-domain, group-disjoint FF++ validation split, but the saved implementation uses a six-way method/original classifier and must be revised and rerun before it can support the intended five-expert meta-routing formulation. This remains one important result—not the sole focus or final definition of the project.
6. The overall contribution is the combined engineering evidence: temporal modeling, domain-shift analysis, domain-generalized comparison, dataset preparation, mobile/server prototyping, and manipulation-specific routing, together with a candid account of what remains unsafe or unproven for deployment.

The report must clearly distinguish:

- **Physical presentation attacks:** print, display replay, masks, and recapture artifacts.
- **Digital manipulation attacks:** face swaps, reenactment, neural rendering, and injected synthetic media.
- **Implemented components:** code and experiments that actually exist in this repository.
- **Target architecture:** the broader edge--cloud--human design proposed for a production financial-verification system.

### Project progression to preserve

The report should follow the actual progression visible in the submissions and repository:

1. **Proposal:** AI-generated/manipulated face detection for secure liveness verification in Pathao Pay, with lightweight mobile screening and stronger server analysis.
2. **Early presentation:** physical-versus-digital attack taxonomy, active/passive liveness, MobileNet-oriented on-device detection, server-side analysis, datasets, security metrics, and early ethical concerns.
3. **Inception phase:** formal complex-engineering framing, a three-tier architecture, planned responsibilities, public-data strategy, economic/environmental analysis, privacy, fairness, financial inclusion, transparency, and accountability.
4. **System-analysis phase:** detailed but mostly target-state requirements, microservice/module design, capture-quality rules, human review, database/API concepts, security controls, and mobile/server model choices.
5. **Temporal research phase:** MobileNetV3 temporal averaging and G2V2Former visual--landmark modeling, followed by LCC-FASD/Celeb-DF-v2 transfer analysis and numerical-stability fixes.
6. **Domain-generalization phase:** GD-FAS under the same two-experiment protocol, plus Asian-Fakes evaluation and SBI/data-preparation work.
7. **Integration phase:** PyTorch Lite K=24 model contract, Flutter capture/inference flow, and a separately demonstrated G2V2Former FastAPI endpoint.
8. **Later specialist-routing phase:** FF++ Xception specialists, universal baseline, CNN router, and XGBoost-head ablation.

Pathao provided the project problem and early context, but the report must state that no private Pathao dataset, grant, or sustained technical collaboration was received. Consequently, the experimental work uses public datasets and independently developed/adapted research implementations.

## 2. Evidence policy for the report

Use sources in this priority order:

1. Saved notebook outputs, result CSV files, code, model contracts, and reproducible artifacts in this repository.
2. The latest report, `all-reports/Temporal_Deepfake_Detection_for_Secure_Liveness_Verification.pdf`, for the previous narrative and experiment interpretation.
3. Week-wise reports for project history, requirements, initial architecture, intended impact, and originally assigned roles.
4. External papers, standards, regulations, and market sources, cited directly from authoritative publications.

Do not convert an earlier plan or target into an achieved result. In particular, the report must not claim that the full three-tier system, human-review console, NID matching, continuous-learning infrastructure, or Pathao Pay production deployment has been completed.

### Source assessment for the newly supplied threat material

- The supplied LinkedIn short link resolves to Aditya Krishna's post, **“Liveness detection fails due to synthetic video attacks not camera access.”** Its valuable design observation is that a digitally injected/virtual-camera stream can bypass the physical camera and present apparently clean media to the model. Use the post as practitioner motivation, not as the sole authority for its percentages.
- Verify the post's quantitative claims against the original [iProov 2025 Threat Intelligence release](https://www.iproov.com/press/annual-identity-verification-threat-intelligence-report), which reports a 2,665% increase in native virtual-camera attacks and a 300% increase in face-swap attacks. Identify the population, time window, and vendor-data limitation whenever using those figures.
- The supplied [ARSA fintech article](https://arsa.technology/blogs/how-to-prevent-deepfake-fraud-with-face-liveness-detection-in-fintech-7li2h4/) is a commercial/vendor source. It is useful for framing passive liveness, active challenge--response, layered controls, and onboarding-friction trade-offs, but its product, speed, pricing, performance, and compliance statements are not independent evidence and should not be used as achieved properties of this project.
- Use [NIST SP 800-63A-4](https://pages.nist.gov/800-63-4/sp800-63a.html) and ENISA's remote-identity-proofing reports as the primary security sources. NIST explicitly treats injection as inserting forged media between capture and comparison and calls for genuine-sensor confidence, protected channels, manipulated-media analysis, and documented human review. ENISA distinguishes camera presentation from direct injection and reports that deepfake presentation and injection were among the hardest biometric attacks for surveyed stakeholders to mitigate.
- Use the original FaceForensics++ and FaceShifter papers/repositories for manipulation definitions, and primary cross-dataset research for the unseen-generator/generalization problem. Do not rely on vendor blogs to define the experimental methods.

## 3. Exact template and formatting requirements

The supplied BUET CSE 450 template requires all of the following:

- A4, one-sided, 12-point report.
- 25 mm margins on all sides.
- Times-style text and mathematics.
- One-and-a-half line spacing.
- Title page, candidates' declaration, acknowledgement, and a maximum one-page abstract.
- Three to six abstract keywords.
- Table of contents, list of figures, and list of tables.
- Seven required chapters and every supplied named section/subsection.
- Figures and tables integrated throughout the report.
- Proper citations and a bibliography; the skeleton does not yet include a bibliography command or `references.bib`, so these must be added.
- Removal of every gray `\guidance{...}` instruction before submission.
- Explicit acknowledgement of third-party code, pretrained models, datasets, copyrighted figures, and generative-AI use.

The existing style also sets Roman page numbering for front matter and Arabic numbering for the main chapters.

## 4. Proposed front matter

### Title page

Fill in the final project title, session, submission month, supervisor name/designation, and the following five candidates after spellings are confirmed:

- Nafis Nahian — 2105007
- Abrar Zahin Raihan — 2105009
- Aritra Debnath — 2105010
- Tamzeed Mahfuz — 2105012
- Ruwad Naswan — 2105051

### Candidates' declaration

Keep the template's accountability language. Add a concise disclosure of any generative-AI assistance used in writing or coding, following supervisor/course policy. The declaration should also cover pretrained weights, public datasets, external implementations, and reused figures.

### Acknowledgement

Give special and prominent thanks to the supervisor for sustained guidance and explicitly acknowledge that the embedding-conditioned specialist-routing idea originated from the supervisor's suggestion. Thank Pathao Pay/Pathao Ltd. for proposing/entrusting the team with the project problem and for the early project context, without implying continued technical participation after the initial weeks.

Do not claim that Pathao or any other organization supplied datasets, compute grants, research funding, or sustained implementation support. Public dataset creators, paper authors, pretrained-model providers, open-source projects, and computing platforms should be cited or attributed in the methodology, references, and intellectual-property inventory; they should not be described as personal project sponsors unless assistance was actually received.

Provisional wording:

> We express our sincere gratitude to our supervisor, [Name and designation], for the guidance, critical feedback, and encouragement provided throughout this project. We are especially grateful for the supervisor's suggestion to investigate embedding-conditioned routing to manipulation-specific deepfake-detection specialists, which led to the specialist-routing experiment reported in this work. We also thank Pathao Pay for entrusting us with the original secure-liveness-verification problem and for the context provided during the initial phase of the project.

Keep this concise. Do not add statements about dataset provision, grants, infrastructure, or continued Pathao collaboration.

### Abstract

Write this last. It should contain, within one page:

- Threat and engineering problem.
- Layered project approach: lightweight/mobile inference, temporal visual--landmark modeling, domain-generalized comparison, and later specialist routing.
- G2V2Former and GD-FAS findings showing strong in-domain PAD performance but weak physical-to-digital transfer, followed by partial improvement after Celeb-DF-v2 fine-tuning.
- The current specialist-routing result as an additional experiment: universal balanced accuracy 76.44% and ROC-AUC 86.32% versus routed-ensemble 84.51% and 91.68% on the group-disjoint FF++ validation split. These figures belong to the current six-way router artifact; replace them if the intended five-expert meta-router is rerun.
- Main limitations: dataset/domain dependence, incomplete fairness evidence, no production integration, and missing cross-dataset specialist-routing validation.
- Practical outcome: a research prototype and mobile/server integration groundwork, not a production-ready security product.

Suggested keywords: **liveness verification, face anti-spoofing, deepfake detection, temporal modeling, domain generalization, biometric security**.

## 5. Chapter-by-chapter content plan

## Chapter 1 — Problem Identification and Formulation

### 1.1 Background and Motivation

Cover:

- Selfie-based onboarding and remote KYC in mobile financial services.
- Why synthetic faces and injected manipulated media expand the attack surface beyond ordinary print/replay attacks.
- Why security, low user friction, mobile-resource limits, privacy, and evolving attacks create conflicting requirements.
- A precise taxonomy separating PAD from deepfake detection.
- The project's evolution from broad Pathao Pay system design through mobile, temporal, graph-guided, and domain-generalized experiments, followed by specialist routing as a later branch.

Add a focused subsection titled **Why Deepfake Attacks Are Difficult to Handle**. It should connect the threat research directly to the system design:

- **Heterogeneous manipulations:** identity swaps, expression reenactment, localized neural rendering, fully synthetic identities, and injected streams leave different—and sometimes conflicting—artifacts. A universal detector can overfit the dominant method, while a specialist can fail outside its own manipulation family.
- **Open-set evolution:** new generators and post-processing pipelines appear after training. Strong in-dataset performance therefore does not imply detection of unseen generators, tools, or attack workflows.
- **Shortcut learning and domain shift:** detectors may learn dataset, codec, camera, resolution, demographic, background, or preprocessing correlations instead of manipulation-invariant evidence. The project's LCC-FASD-to-Celeb-DF-v2 and Asian-Fakes results are direct evidence of this difficulty.
- **Artifact destruction:** resizing, social-media recompression, blur, denoising, frame interpolation, and camera recapture can weaken pixel-level traces. Conversely, a detector may mistake ordinary compression or device noise for fake evidence.
- **Plausible liveness cues:** modern synthetic or reenacted video can contain blinking, speech, head motion, and temporally coherent expressions, so basic motion checks or a fixed challenge do not necessarily prove genuine presence.
- **Capture-channel compromise:** a virtual camera, emulator, hooked API, or injected stream can bypass the physical sensor. This is a provenance/integrity problem as well as a classification problem; a better face classifier alone cannot authenticate a poisoned input path.
- **Real-time and mobile constraints:** temporal, landmark, frequency, and multi-model analysis may improve coverage but increases latency, memory, energy, bandwidth, and privacy exposure.
- **High-stakes operating trade-offs:** a permissive threshold increases fraud risk, while an aggressive threshold can exclude legitimate users. Attackers can also adapt through repeated probing, so thresholds and models require monitoring and controlled updates.
- **Human review is not a complete defense:** highly realistic or injected media can deceive reviewers too. Review must be supported by capture provenance, model evidence, transaction context, and an appeal process rather than unaided visual inspection.

The key conclusion should be: **deepfake resistance requires both media analysis and capture-channel assurance**. Connect the layered architecture to camera/session integrity, device or sensor attestation where feasible, authenticated transport, active/passive liveness, temporal and spatial detection, risk-based escalation, and accountable review. Clearly label these controls as requirements or future design where they are not implemented.

Evidence:

- Week 3 proposal and Week 5 presentation for original motivation.
- Latest temporal report for the physical-versus-digital attack distinction.
- Current repository for the implemented scope.
- NIST SP 800-63A-4 and ENISA remote-identity-proofing guidance for injection, genuine-sensor assurance, and layered countermeasures.
- Original FaceForensics++/FaceShifter publications and current cross-dataset research for manipulation diversity and generalization limits.
- The supplied LinkedIn and ARSA articles only as clearly identified practitioner/vendor context, with quantitative claims traced to their original sources.

### 1.1.1 Attack and Manipulation Taxonomy

Include one taxonomy figure and one mapping table with three separate axes:

1. **Delivery path:** physical presentation to a camera; deepfake displayed/recaptured through a camera; or direct digital injection/virtual camera that bypasses the genuine sensor.
2. **Manipulation goal:** identity replacement/face swap; expression or pose reenactment; localized neural rendering; fully synthetic identity; or multimodal/document manipulation.
3. **Evidence used by this project:** spatial texture/artifacts, domain-generalized features, temporal frame evidence, facial-landmark motion, and manipulation-specific specialist evidence.

State exactly which digital manipulations were evaluated in the FF++ routing experiment:

| FF++ method | Manipulation family | What changes | Role in this project |
| --- | --- | --- | --- |
| Deepfakes | Learning-based identity swap | Source identity is synthesized onto a target performance | One binary Xception specialist and one routing class/target in the current artifact |
| FaceSwap | Graphics-based identity swap | A source face is geometrically transferred and blended into a target | One binary specialist and routing target |
| FaceShifter | Learned, high-fidelity, occlusion-aware identity swap | Identity is replaced while target attributes and occlusions are handled by a two-stage method | One binary specialist and routing target |
| Face2Face | Graphics-based facial reenactment | Source expressions are transferred to the target while retaining target identity | One binary specialist and routing target |
| NeuralTextures | Learned neural rendering/reenactment | A learned neural texture modifies facial appearance, particularly expression-related regions | One binary specialist and routing target |

`original` is the genuine/reference class in FF++ and **is not a deepfake type**. Fully synthetic faces, lip-sync-only attacks, audio deepfakes, document deepfakes, diffusion-generated identities, and live virtual-camera injection are important threats but were not separate specialist classes in the reported FF++ experiment. Do not imply experimental coverage of them.

### 1.2 Problem Statement

Formulate two nested problems.

**System-level problem:** Given a selfie or short facial video from a verification session, produce a calibrated risk score and PASS/FAIL/REVIEW decision while limiting attack acceptance, legitimate-user rejection, latency, resource use, and privacy exposure.

**Later specialist-routing subproblem (intended final formulation):** Given a single preprocessed facial frame `x`, select the most suitable one of five binary manipulation specialists and use that specialist to estimate `P(fake | x)`. The meta-router is an expert selector, not the real/fake detector and not an `original` classifier.

Define it mathematically:

```text
z = phi(x)                                  embedding for the current frame
q_e(z) = P(E* = e | z),  e in E             router distribution over five experts
E = {Deepfakes, Face2Face, FaceShifter,
     FaceSwap, NeuralTextures}
e_hat = argmax_e q_e(z)                      hard expert selection
p_hat(fake | x) = s_e_hat(x)                 selected binary expert's fake probability
```

Here `phi` is the router feature extractor, `E*` is the best-expert target, and `s_e` is a binary real-versus-method specialist. Every input—including a genuine frame—is transferred to one of the five specialists; there is no `original` route and no `1 - P(original)` fallback. This should be called an **embedding-conditioned meta-routed specialist ensemble** or **hard specialist-routing model**, not simply “MoE.” The repository directory may remain `DeepFake-MoE/` as a historical path.

The report must define how `E*` is obtained. To claim `P(best expert | embedding)`, generate leakage-safe/out-of-fold predictions from all five specialists and label each routing example with the expert having the lowest binary loss or highest correct-class likelihood, with a documented tie policy. If fake-method identity is used as the routing label instead, the honest formulation is `P(manipulation method | embedding)` and “matched manipulation specialist” is only a proxy for “best expert.” Real frames are especially important: without an `original` route, they still require a valid best-expert target rather than being omitted without justification.

**Current-code discrepancy:** `DeepFake-MoE/capstone-xception.ipynb` and `xception-xgb.ipynb` currently define six router classes—`original` plus the five manipulation methods—and use `1 - P(original)` when that route wins. The reported routed metrics and 81.12% router accuracy belong to that six-way implementation. They cannot be relabeled as results of the five-expert selector. Revise the notebooks, refit both CNN and XGBoost router heads, and rerun the ensemble evaluation before presenting the intended formulation as implemented.

Define the optimization/evaluation quantities: balanced accuracy, ROC-AUC, average precision, real accuracy, fake accuracy, FAR/FRR/HTER where available, latency, and model footprint.

### 1.3 Complexity of the Problem

Populate the required P1--P7 table with project-specific evidence:

- **P1 / K3, K4, K5, K6, K8:** probability and optimization, deep learning, computer vision, system design, mobile deployment, and research literature.
- **P2:** security versus false rejection, accuracy versus latency/memory, privacy versus server analysis, specialization versus generalization.
- **P3:** no single obvious detector works across physical and digital attack families; original analysis and experiments were required.
- **P4:** unseen generators, compression, dataset shift, unstable graph-guided attention, and router errors are non-routine issues.
- **P5:** ISO PAD guidance helps evaluation but does not completely specify digital deepfake/injection defense.
- **P6:** end users, the financial-service provider, reviewers, regulators, developers, and fraud investigators have differing needs.
- **P7:** capture, preprocessing, mobile inference, temporal/server inference, routing, expert selection, decision policy, privacy, and review are interdependent.

### 1.4 Project Objectives and Scope

Use numbered, verifiable objectives that Chapter 5 can evaluate:

1. Formulate a layered threat model and verification architecture covering physical presentation attacks and digital facial manipulation.
2. Implement lightweight spatial and temporal baselines suitable for mobile-oriented liveness screening.
3. Investigate explicit temporal and facial-landmark modeling through a G2V2Former-inspired visual--graph architecture.
4. Measure the physical-PAD-to-deepfake domain gap and compare G2V2Former with the domain-generalized GD-FAS baseline under a common protocol.
5. Prepare leakage-aware public-data pipelines, including LCC-FASD, Celeb-DF-v2, Asian-Fakes/SBI, and FF++ experiments.
6. Investigate whether manipulation-specific Xception specialists and embedding-conditioned best-expert routing improve over a universal deepfake classifier.
7. Prototype mobile temporal inference and an experimental server-side inference path.
8. Analyze privacy, fairness, user autonomy, accountability, security, deployment, and sustainability constraints throughout the design and evaluation.

Scope exclusions must be explicit: production Pathao integration, certification, NID database integration, a completed reviewer dashboard, comprehensive demographic validation, and defense against every generator/attack type. The current prototype also does not implement virtual-camera detection, device/sensor attestation, emulator/root detection, cryptographic capture provenance, or multimodal document/voice-deepfake defense.

## Chapter 2 — Preliminary Research

### 2.1 Literature Review

Organize by ideas, not by paper:

- Spatial artifact detection and Xception/FaceForensics++.
- Texture, frequency, and blending-boundary evidence.
- Temporal aggregation and lightweight MobileNet-based video PAD.
- Facial-landmark and graph-guided temporal modeling (G2V2Former).
- Domain generalization and vision-language approaches (GD-FAS).
- Embedding-conditioned meta-routing, hard specialist selection, oracle/best-expert targets, and routing failure. Discuss classical mixture-of-experts only as related literature, not as the chosen name for this implementation.
- Calibration and security-oriented biometric metrics.

The synthesis should establish several connected gaps:

- Frame-level evidence can miss motion and landmark inconsistencies that appear over time.
- Presentation-attack cues do not automatically transfer to digital deepfakes.
- Domain-generalized methods can remain highly source-domain dependent and require direct target-domain exposure.
- Strong aggregate metrics do not establish fairness, calibration, or safety for financial decisions.
- Universal deepfake classifiers must absorb heterogeneous manipulation distributions, whereas specialists can be strong on their own method but fail across methods; embedding-conditioned specialist selection is one later response to this issue.

### 2.2 Existing Solutions and Technologies

Discuss:

- Active versus passive liveness.
- Presentation attacks versus digital injection, including why sensor/session provenance cannot be replaced by image classification accuracy.
- Commercial verification/PAD systems only with verifiable, cited claims.
- Open-source/research alternatives represented in this repository.
- On-device screening, cloud analysis, and human escalation.

End with the broader gap addressed by this project: practical liveness verification needs complementary spatial, temporal, domain-generalized, and attack-specific evidence, yet the transfer, deployment, fairness, and privacy properties of those components must be measured rather than assumed.

### 2.3 Market and User Research

Use actual evidence from industry-partner discussions, interviews, or published Bangladesh digital-finance data. The current repository does not contain primary user research, so do not invent it. If direct research was not conducted, state that limitation and use cited secondary evidence.

### 2.4 Feasibility Study

Assess:

- Technical feasibility: public data, pretrained backbones, Kaggle GPUs, Flutter/PyTorch Lite, FastAPI.
- Economic feasibility: open-source tooling versus compute/storage and model-serving costs.
- Operational feasibility: capture quality, connectivity, update process, fallback/review.
- Legal/privacy feasibility: consent, biometric-data minimization, retention, access control, and current Bangladesh requirements.

## Chapter 3 — Requirements Analysis

### 3.1 Project Objectives and Constraints

Create a traceable table with requirement ID, stakeholder, acceptance criterion, evidence, and final status.

Candidate functional requirements:

- FR-1 capture a front-camera facial sequence.
- FR-2 establish reasonable confidence that frames originate from the intended live sensor/session; detect or constrain virtual cameras, emulators, replayed buffers, and API/process injection where platform capabilities permit.
- FR-3 preprocess frames consistently with the deployed model contract.
- FR-4 classify a 24-frame clip locally and return calibrated real/fake confidence rather than only a hard label.
- FR-5 apply a documented confidence/quality policy that can accept a clear low-risk case, request recapture, reject or retry a clear attack, or escalate an uncertain/high-risk case.
- FR-6 run a stronger second-stage detector when escalation is available; candidate components are temporal G2V2Former, domain-generalized GD-FAS, and a universal or meta-routed Xception branch.
- FR-7 normalize/calibrate second-stage scores and combine them under an auditable decision policy.
- FR-8 return score, label, model version, timing, route taken, and reason code without exposing attack-enabling detail to the user.
- FR-9 refer persistently ambiguous or conflicting high-impact cases to an authorized human reviewer when that workflow is implemented.
- FR-10 remove temporary raw captures after processing.

Candidate non-functional requirements:

- NF-1 security-oriented FAR/FRR/HTER or balanced-accuracy targets.
- NF-2 latency and memory targets measured on named hardware.
- NF-3 group/video-disjoint evaluation and reproducibility.
- NF-4 privacy and retention constraints.
- NF-5 accessibility and retry/fallback behavior.
- NF-6 maintainability through model contracts and versioned artifacts.
- NF-7 capture-channel integrity, authenticated transport, auditability, and resistance to repeated probing.

Earlier reports listed ambitious targets such as ACER below 5%, EER below 3%, AUC above 0.98, and total verification below 2.5 seconds. Treat these as target requirements and report whether they were met; do not present them as achieved.

### 3.2 Regulatory Requirements and Standards

At drafting time, verify the current editions and applicability of:

- ISO/IEC 30107 series for presentation attack detection terminology and testing.
- Relevant ISO/IEC biometric-performance standards.
- OWASP mobile/API security guidance for the app/server path.
- Accessibility guidance such as WCAG where applicable.
- Current Bangladesh Bank e-KYC/MFS requirements and current Bangladesh privacy/cybersecurity law.
- ACM, IEEE, and IEB professional/ethical codes.

For every item, state why it applies, what design choice it affects, and whether the prototype actually demonstrates compliance. Do not claim certification.

### 3.3 Formulation of Solutions

Compare genuinely different alternatives against common criteria:

1. Single universal spatial Xception.
2. Lightweight temporal MobileNetV3 with average pooling.
3. Graph-guided visual/landmark transformer.
4. Domain-generalized vision-language FAS.
5. Embedding-conditioned hard routing among manipulation-specific Xception specialists.

Criteria: in-domain discrimination, cross-domain generalization, mobile suitability, latency, memory/storage, interpretability, data needs, robustness, and implementation complexity.

Conclude that embedding-conditioned specialist routing is a promising **deepfake branch candidate**, not a replacement for physical PAD, capture-channel assurance, or temporal liveness cues. Its intended five-specialist form is pending implementation and reevaluation.

## Chapter 4 — System Design and Implementation

### 4.1 Functional Design and Sub-problem Partitioning

Make the two-layer decision pipeline one of the principal visual explanations of the report. Show at least four related diagrams:

1. **As-built research system:** data preparation → model families → evaluations → Flutter local model and separately demonstrated FastAPI server.
2. **Target two-layer verification pipeline:** capture provenance/integrity and quality gate → on-device temporal MobileNetV3 → confidence-based decision or escalation → stronger server analysis → calibrated decision/retry → optional human review for unresolved hard cases.
3. **Temporal hierarchy:** inexpensive first-layer feature aggregation versus richer second-layer ordered visual/landmark interactions.
4. **Implementation-status view:** distinguish integrated, separately implemented/evaluated, and proposed components.

Use one consistent status legend in every architecture figure:

- **Solid/green:** implemented and integrated in the current Flutter flow.
- **Solid/amber:** implemented or evaluated separately, but not connected end to end.
- **Dashed/blue:** proposed integration or decision logic.
- **Review boundary:** proposed human involvement; no reviewer workflow is currently implemented.

The target pipeline figure should express the following logic without inventing numerical thresholds:

```text
Front-camera sequence
        |
Capture provenance/integrity checks [proposed]
  genuine sensor/session, virtual-camera/emulator/injection indicators,
  authenticated protected channel
        |
Face and quality checks -------- poor quality ----> recapture guidance
        |
Layer 1: on-device temporal MobileNetV3
24 frames -> shared CNN features -> temporal mean -> logits -> P(fake)
        |
        +-- P(fake) <= tau_pass ------------------> candidate pass
        +-- tau_pass < P(fake) < tau_attack ------> Layer 2 escalation
        +-- P(fake) >= tau_attack ----------------> retry/reject or server confirmation,
                                                    depending on security policy

Layer 2 candidate evidence
  G2V2Former: 8 frames + 68-landmark graphs -> explicit temporal score
  GD-FAS: selected frame(s) -> domain-generalized spatial/PAD score
  Xception: selected frame(s) -> universal or hard-routed specialist score
        |
Score calibration/fusion and risk-aware decision policy [proposed]
        +-- sufficiently clear -------------------> pass or fail/retry
        +-- conflicting/ambiguous hard case ------> human review [proposed]
```

`tau_pass` and `tau_attack` are placeholders, not current settings. Select them later from validation data using FAR/FRR, calibration, capture quality, and the asymmetric costs of fraud and false rejection. The current app instead applies a single uncalibrated `P(fake) = 0.5` boundary, immediately accepts a predicted real sample, and displays/retries a predicted spoof sample. It does not yet call Layer 2.

The three Layer-2 models are candidate or complementary evidence sources, not a claim that all three currently execute for every request. The final design should decide experimentally whether to select one model, run a risk-dependent subset, or fuse calibrated outputs. A high-confidence attack may still be server-confirmed when minimizing false rejection is more important than saving server work.

Partition the implementation into:

- MobileNetV2 single-frame PAD baseline.
- MobileNetV3 temporal-average model and `.ptl` export.
- G2V2Former visual/landmark temporal model.
- GD-FAS comparison baseline.
- LCC-FASD, Celeb-DF-v2, Asian-Fakes/SBI, and FF++ data processing.
- Flutter capture/inference UI.
- Experimental FastAPI endpoint.
- Universal Xception baseline, five manipulation-specific specialists, embedding-conditioned meta-router, and XGBoost-head ablation in the historically named `DeepFake-MoE/` directory.

Add a component-role/status table so readers can see where temporal modeling actually occurs:

| Component | Input and temporal mechanism | Intended role | Current status |
| --- | --- | --- | --- |
| Capture-channel assurance | Sensor/session/device provenance rather than a learned temporal detector | Prevent injected or virtual-camera media from being trusted as genuine capture | Required target-state control; not implemented in the current Flutter prototype |
| MobileNetV3 temporal-average model | Consecutive frames; shared 960-dimensional per-frame features averaged across time | Fast Layer-1 mobile screening and confidence generation | Exported as K=24 PyTorch Lite and integrated into Flutter; current training script records K=10, so checkpoint/export provenance must be reconciled |
| G2V2Former | Eight uniformly sampled frames; visual-patch attention plus motion guidance from 68-landmark graphs | Stronger Layer-2 temporal analysis | Trained/evaluated and demonstrated through a separate FastAPI notebook; not connected to the app |
| GD-FAS | Image-based CLIP ViT-B/16 features; no learned temporal module in the evaluated implementation | Domain-generalized PAD/spatial evidence in Layer 2 or comparison baseline | Evaluated under the common protocol; not served or integrated |
| Universal/meta-routed Xception | Individual 299x299 frames; embedding-conditioned hard specialist selection, but no temporal module | Digital-manipulation evidence in Layer 2 | Current metrics come from a six-way original/method router; intended five-expert selector is not yet rerun, served, or integrated |
| Score fusion and human review | Calibrated model/quality evidence accumulated across the decision path | Resolve model disagreement and high-impact hard cases | Proposed only |

### 4.2 Design Refinement and Simulation

Document the refinements as engineering decisions:

- Lightweight per-frame modeling was extended to temporal average pooling so multiple observations contribute to a clip decision. Each frame passes through the shared MobileNetV3 feature extractor, producing a `[B,K,960]` sequence; mean pooling across `K` produces the clip feature used by the binary classifier. In full-video Python inference, raw logits from non-overlapping clips are averaged before one final softmax.
- G2V2Former added explicit visual-patch and 68-landmark graph streams with masked-reconstruction pretraining and graph-guided temporal interaction.
- G2V2Former numerical fix: collision-sensitive scatter-sum changed to scatter-mean, guidance clamped, learning-rate warmup added, and safer mixed precision used.
- Zero-shot LCC-FASD-to-Celeb-DF-v2 results motivated direct deepfake fine-tuning and a common G2V2Former/GD-FAS evaluation protocol.
- GD-FAS was introduced to test whether domain-invariant CLIP-based features generalize better than the graph-guided temporal architecture.
- Asian-Fakes/SBI preparation was added as a limited demographic/generalization stress test, with its provenance and split limitations recorded.
- Original-video-group 90/10 FF++ splitting was used to avoid frame/video leakage in the later direct-deepfake experiments.
- Aligned FF++ real/fake extraction produced 1,000 video groups, 100 frames per method/video, and 600,000 total frames.
- Specialists trained per manipulation method.
- Current six-way router followed by either one selected specialist or an `original` fallback; record this as the evaluated legacy formulation, not the desired final method.
- Intended refinement: a 2,048-dimensional frame embedding feeds a five-way meta-routing head that estimates `P(best expert | embedding)` and transfers every frame to exactly one binary specialist.
- XGBoost router-head experiment as an alternative embedding-to-route model that did not outperform the CNN head under the current six-way formulation; it must be refit for any five-expert comparison.
- Fixed mobile inference contract `[1, 24, 3, 224, 224]`, RGB, ImageNet normalization, two raw logits.

Make the contrast between the two temporal designs explicit:

- **Layer 1 uses weak/order-insensitive temporal aggregation:** it observes multiple consecutive frames but averages their representations. This is computationally simple and suitable for a mobile gate, although it cannot explicitly model frame order or long-range motion.
- **Layer 2 G2V2Former uses explicit/order-aware temporal reasoning:** it models interactions across the eight-frame visual sequence while facial-landmark graph motion guides temporal attention. This is the project's stronger temporal analysis path.
- **GD-FAS and Xception are spatial complements:** the evaluated versions operate on individual frames. Sampling several frames or aggregating their calibrated scores would create video-level evidence, but it would not make their present architectures temporal models. Any such aggregation belongs in future integration work unless it is implemented and evaluated before submission.

For the Layer-1 figure, draw: `24-frame capture -> identical crop/resize/normalization -> shared MobileNetV3 for each frame -> h_1...h_24 -> mean(h_t) -> linear logits [real,fake] -> softmax P(fake) -> routing policy`. Add a smaller annotation that the training code currently uses K=10 chunks whereas the exported artifact is traced for K=24; the architecture is K-agnostic before tracing, but the exact checkpoint/export combination still needs verification.

For the Layer-2 figure, draw three lanes that converge only at a proposed calibration/fusion block:

- G2V2Former lane: eight frames and landmark extraction -> visual patches + landmark graphs -> spatial/temporal interaction -> liveness/deepfake score.
- GD-FAS lane: selected image frame(s) -> CLIP visual/text representation and domain-generalization mechanism -> PAD score.
- Xception lane: selected frame(s) -> universal baseline, or frame embedding -> five-way meta-router -> selected binary specialist -> deepfake score. Mark this as the intended rerun; include a separate annotation that the recorded results currently use a six-way original/method router.

Use dashed arrows for all mobile-to-server calls, multi-model fusion, and human escalation because those links are not active in the current application.

Call the intended method an **embedding-conditioned meta-routed specialist ensemble** or **hard specialist-routing model**. Avoid “MoE” as the primary name: the router makes one discrete expert assignment from a learned embedding and the chosen binary specialist performs the real/fake decision. Classical mixture-of-experts terminology may appear only in related work, with the difference stated explicitly.

### 4.3 Application of Tools

Justify and state limitations of:

- PyTorch/torchvision for training and export.
- Kaggle GPUs for experiments.
- OpenCV/PIL for video and image processing.
- `face_alignment`/landmarks for G2V2Former.
- XGBoost for the router-head ablation.
- scikit-learn for metrics.
- Flutter/Dart and `flutter_pytorch_lite` for mobile inference.
- FastAPI/Uvicorn for the server prototype.
- Git/GitHub for version control.

### 4.4 Implementation

Describe exact implementations with references to repository artifacts:

- `mnetv2-anti-spoof-baseline/`: single-frame LCC-FASD baseline, webcam inference, checkpoint conversion, and memory profiling utilities.
- `spatio-temporal-mnetv3/`: temporal MobileNetV3 training, full-video inference, export, and model contract. Record both aggregation levels: mean pooling of per-frame features inside a clip, and mean aggregation of raw clip logits in the full-video inference script.
- `g2v2former/`: eight-frame visual-patch/68-landmark graph model, masked pretraining, supervised fine-tuning, common cross-dataset evaluation, latency study, and FastAPI server notebook.
- `gd-fas/`: official CLIP ViT-B/16-based GD-FAS implementation adapted to the same LCC-FASD, Celeb-DF-v2, and Asian-Fakes two-experiment protocol, including recorded HTER/AUC results and documented deviations from official defaults.
- `data-processing/prep-sbi-extra.ipynb`: paired real/SBI preparation from South Asian, Asian, and non-Asian sources, including face-quality filtering and split limitations.
- `data-processing/image-from-ff.ipynb`: FF++ C23 frame extraction and leakage-aware split.
- `lib/pages/liveness_page.dart`: 24-frame capture, preprocessing, raw-tensor inference, softmax decision, and temporary-file deletion.
- `DeepFake-MoE/capstone-xception.ipynb`: historically named directory containing five specialists, a universal baseline, and the current six-way `original`/method router. State that this notebook does not yet implement the intended five-expert best-model router.
- `DeepFake-MoE/xception-xgb.ipynb`: frozen 2,048-dimensional router embeddings and current six-class XGBoost-head ablation; it also requires a five-expert refit.

State code reality precisely: the Flutter app currently captures 24 consecutive frames, constructs one `[1,24,3,224,224]` tensor, performs local MobileNetV3 inference, applies softmax, and uses a fixed 0.5 boundary. The second-stage HTTP call is commented out. The G2V2Former FastAPI server was demonstrated separately but is not currently wired into the app. GD-FAS, Xception routing, cross-model score fusion, confidence-band routing, and human review are also not part of the running mobile flow.

### 4.5 Deployment

Separate current and intended deployment:

- **Current:** local Flutter prototype with bundled PyTorch Lite model; separately demonstrated Kaggle/FastAPI endpoint.
- **Intended:** versioned local model, capture provenance/integrity and quality gates, calibrated two-threshold escalation policy, authenticated encrypted server endpoint, selected/fused second-stage evidence, monitoring, rollback, raw-capture minimization, and an accountable review/appeal path for hard cases.

Include resource evidence only when measured. The model contract reports a 13.8 MiB input tensor for one 24-frame clip. Do not reuse old RAM/latency estimates as measured values unless their profiling artifacts are available.

## Chapter 5 — Investigation and Evaluation

This should be the technical core of the final report.

### 5.1 Experimental Investigation

Use explicit research questions:

- **RQ1:** How much do lightweight temporal aggregation and explicit visual--landmark temporal modeling contribute to liveness/PAD detection?
- **RQ2:** Do models trained for physical PAD transfer to digital deepfake datasets without target-domain training?
- **RQ3:** How do G2V2Former and the domain-generalized GD-FAS baseline compare under the same LCC-FASD, Celeb-DF-v2, and Asian-Fakes protocol?
- **RQ4:** How does Celeb-DF-v2 fine-tuning change target performance, source-domain retention, and transfer to Asian-Fakes?
- **RQ5:** Do manipulation-specific specialists outperform a universal deepfake classifier, and can an embedding-conditioned meta-router learn `P(best expert | embedding)` well enough to exploit that specialization?
- **RQ6:** Does an XGBoost router head improve over the trained CNN linear head?
- **RQ7:** Can a calibrated first-stage confidence policy reduce server use while preserving an acceptable FAR/FRR operating point, and which samples should be escalated?
- **RQ8:** What accuracy, fairness, privacy, latency, resource, human-oversight, and integration limitations remain before deployment?

#### Temporal and domain-generalization experiments

Give G2V2Former and GD-FAS full treatment rather than using them only as background.

**G2V2Former-inspired implementation:**

- Eight uniformly sampled frames per video.
- Visual stream operating on image patches and a graph stream operating on 68 facial landmarks.
- Separate masked-reconstruction pretraining for visual and graph streams, followed by supervised fusion/fine-tuning.
- Graph-derived motion guidance injected into temporal visual attention.
- LCC-FASD for physical print/replay PAD; Celeb-DF-v2 for digital face swaps; Asian-Fakes as an additional transfer stress test.
- Numerical-stability revision after attention-guidance collisions produced overflow/NaN behavior.
- Separate latency/API work to assess server-side feasibility.

**GD-FAS comparison:**

- Official GD-FAS implementation with CLIP ViT-B/16, textual class prompts, group-wise scaling, and orthogonal/Gram--Schmidt feature decomposition.
- Adapted to the same datasets, metrics, Celeb-DF caps, and two-experiment structure as G2V2Former.
- Experiment 1 trains on LCC-FASD; Experiment 2 starts from that checkpoint and fine-tunes on a Celeb-DF-v2 training split disjoint from the official test list.
- Document deviations: single source domain, adapter datasets, deterministic middle-frame evaluation, altered batch/evaluation cadence, and center-crop fallback in the recorded Celeb-DF run.

Common recorded results:

| Model/experiment | LCC-FASD HTER / AUC | Celeb-DF-v2 HTER / AUC | Asian-Fakes (all) HTER / AUC |
| --- | ---: | ---: | ---: |
| G2V2Former, train LCC-FASD | 22.38 / 80.71 | 59.71 / 37.14 | 50.13 / 49.82 |
| G2V2Former, then fine-tune Celeb-DF-v2 | 33.50 / 65.14 | 43.32 / 57.22 | 49.13 / 50.33 |
| GD-FAS, train LCC-FASD | 4.55 / 99.69 | 52.99 / 50.49 | 48.33 / 52.98 |
| GD-FAS, then fine-tune Celeb-DF-v2 | 7.07 / 99.16 | 41.04 / 64.35 | 44.58 / 57.94 |

All entries are percentages. Interpret them carefully:

- GD-FAS is substantially stronger than G2V2Former in-domain on LCC-FASD.
- Neither LCC-only model provides reliable zero-shot Celeb-DF-v2 protection; G2V2Former is below chance by AUC and GD-FAS is approximately at chance.
- Direct Celeb-DF-v2 fine-tuning improves both models on digital deepfakes, but neither becomes a robust general detector.
- G2V2Former loses considerable LCC-FASD performance after fine-tuning, demonstrating forgetting/source-retention tension.
- GD-FAS retains stronger LCC-FASD performance and transfers somewhat better to Celeb-DF-v2 and Asian-Fakes, but Asian-Fakes performance remains weak.
- Asian versus non-Asian scores are not sufficient evidence of demographic fairness because dataset construction, identities, manipulation process, and sample comparability are limited.

The latest temporal PDF reports a best in-domain G2V2Former HTER of 21.71%, while current notebook outputs contain 22.38% and 24.07% values from different runs/protocol stages. The final report must select and document one authoritative run rather than mixing them.

#### Lightweight temporal/mobile experiment

The earlier ROSE-Youtu temporal MobileNetV3 notebook reports 98.46% accuracy, 99.88% AUC, 1.39% EER, and 1.36% HTER. Label it as an earlier physical-PAD result. Do not treat it as evaluation of the current Celeb-DF K=24 mobile artifact without rerunning and verifying that exact checkpoint and protocol.

Explain the current temporal pipeline separately from that earlier result:

- Training code divides videos into non-overlapping K=10 clips, applies the same random augmentation to every frame in a clip, extracts one 960-dimensional MobileNetV3 feature per frame, and averages those features before classification.
- The mobile export traces the same averaging architecture for a fixed K=24 input contract. The architecture can accept different K values before tracing, but the report must prove which checkpoint produced the shipped K=24 artifact.
- The Python full-video inference path forms non-overlapping K=24 clips, repeats the last frame when the final clip is short, averages raw clip logits across the video, and applies softmax once.
- The Flutter app currently collects one consecutive 24-frame clip and returns its softmax score; it does not perform the full-video multi-clip aggregation or confidence-band escalation.
- Mean pooling makes the first stage lightweight but order-insensitive. Therefore, present it as **temporal evidence aggregation**, not as an explicit motion/sequence model equivalent to G2V2Former.

#### Later manipulation-specific routing experiment

Present the **embedding-conditioned specialist-routing investigation** after the temporal/domain-generalization work as a separate experiment motivated by heterogeneous digital manipulation artifacts. Use `DeepFake-MoE/` only when referring to the repository path.

Protocol:

- Dataset: FaceForensics++ C23.
- Data categories: genuine `original` frames plus five manipulated types—Deepfakes, Face2Face, FaceShifter, FaceSwap, and NeuralTextures. Group these into identity swaps, reenactment, and neural rendering as defined in the Chapter 1 taxonomy.
- 1,000 original-video pair groups; 900 train and 100 validation groups.
- 100 extracted frames per video/class: 540,000 train and 60,000 validation frames.
- Validation is group/video-disjoint from training.
- Backbone: Cadene/FF++-style Xception, about 20.81 million parameters per model, pretrained backbone, full fine-tuning.
- Input: 299×299 with Xception-style normalization and on-the-fly blur/JPEG/flip augmentation.
- Five binary real-versus-method specialists and one binary universal model.
- **Recorded router:** one six-class Xception head over `original` plus five manipulation labels; its penultimate representation is 2,048-dimensional. The XGBoost ablation replaces its linear head using those frozen embeddings.
- **Intended router:** one five-way meta-model over the five specialists, with no `original` route, trained to estimate `P(best expert | embedding)`. Its results are pending a leakage-safe target definition and rerun.
- Maximum 15 epochs, batch size 128, AdamW, initial learning rate `1e-4`, weight decay `1e-5`.
- Fixed binary score threshold 0.5 for the saved comparison.

Results:

| Model | Accuracy | Balanced accuracy | ROC-AUC | Average precision | Real accuracy | Fake accuracy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Universal Xception | 81.83% | 76.44% | 86.32% | 96.62% | 68.37% | 84.52% |
| Current six-way CNN-routed ensemble | 84.44% | 84.51% | 91.68% | 98.22% | 84.62% | 84.40% |
| Current six-way XGBoost-head ensemble | 83.49% | 82.39% | 88.73% | 97.73% | 80.73% | 84.05% |

The currently recorded comparison is universal versus the six-way CNN-routed ensemble:

- Balanced accuracy: **+8.07 percentage points**.
- ROC-AUC: **+5.36 percentage points**.
- Overall accuracy: **+2.61 percentage points**.
- Real accuracy: **+16.25 percentage points**.
- Fake accuracy: essentially unchanged (**−0.12 percentage points**).

Per-method balanced accuracy:

| Method | Own specialist | Universal | Current six-way routed ensemble |
| --- | ---: | ---: | ---: |
| Deepfakes | 94.86% | 79.81% | 88.62% |
| Face2Face | 92.36% | 78.47% | 85.20% |
| FaceShifter | 93.24% | 75.70% | 87.64% |
| FaceSwap | 90.37% | 75.58% | 84.98% |
| NeuralTextures | 80.28% | 72.66% | 76.11% |

Interpretation:

- Specialists are strong only on their own manipulation and are mostly near chance on other methods.
- The current router converts some of that specialization into a usable decision path and improves every per-method comparison against the universal model.
- The routed system does not reach oracle specialist performance because route errors expose samples to the wrong expert.
- NeuralTextures is the hardest method and is frequently confused with originals.
- The CNN router is better than the XGBoost-head replacement in both routing and final ensemble metrics.
- The improvement is meaningful but remains in-domain and frame-level; it must not overshadow the temporal and domain-generalization findings or be presented as the completed liveness system.
- None of these observations demonstrates `P(best expert | embedding)` yet, because the current target is six-way source-method/original classification. Keep the result as a useful precursor and replace it after the intended meta-router rerun.

### 5.2 Performance Evaluation

Evaluate every objective and requirement using a traceability matrix. Use status values **met**, **partially met**, **not met**, or **not measured**.

Include:

- MobileNetV3, G2V2Former, and GD-FAS results with clearly separated datasets and protocols.
- If the cascade is implemented before submission, first-stage calibration plots, selected `tau_pass`/`tau_attack`, escalation rate, end-to-end FAR/FRR, and conditional Layer-2 performance on the actually escalated hard cases. Otherwise, keep these as future-work requirements.
- G2V2Former/GD-FAS source-domain, target-domain, and retention/generalization comparisons.
- Asian-Fakes subgroup results with an explicit warning that they are not a complete fairness audit.
- Mobile artifact correctness contract and, if rerun, real-device latency/memory.
- G2V2 latency pilot on Tesla T4: about 1,269.9 ms mean end-to-end for an eight-frame video, 129.4 ms model time, measured over only five runs; present this as a small pilot, not a stable service-level result.
- Universal/specialist/routed Xception comparison, with the routing formulation named explicitly.
- Current router accuracy and confusion matrix: 81.12% six-way accuracy/balanced accuracy. Do not carry this number into the intended five-expert result table.
- For the intended router, report five-way top-1 routing accuracy, oracle-best-expert agreement, routing regret relative to the oracle, final binary metrics, route distribution for genuine and fake frames, and comparison with always-best-single and universal baselines.
- Cross-method specialist matrix and XGBoost-head ablation.

### 5.3 Deviations and Design Revisions

Discuss:

- Broader three-tier production scope narrowed to measurable ML prototypes.
- Physical PAD performance did not imply deepfake performance.
- G2V2Former instability and its numerical fix.
- Direct deepfake training and specialist routing introduced in response.
- XGBoost router head did not improve the primary CNN router.
- Current mobile app has local inference but no active server escalation.
- The intended confidence-band cascade, multi-model fusion, and human-review handoff remain design proposals rather than evaluated end-to-end behavior.
- Earlier performance targets remain unmet or unmeasured for the complete system.

## Chapter 6 — Project Management, Teamwork, and Impact

### 6.1 Project Management and Finance

#### 6.1.1 Planning and Risk Management

Replace the template's generic Gantt with actual project dates and milestones:

- Proposal and initial requirements.
- System design and three-tier architecture.
- MobileNet baselines and Flutter prototype.
- FF++ data preparation.
- G2V2Former and domain-shift experiments.
- GD-FAS and Asian-Fakes comparison.
- Temporal mobile integration.
- Specialist routing and router-head ablation.
- Final evaluation and report.

Risks: dataset leakage, domain shift, class imbalance, training instability, missing checkpoints, hardware dependence, model obsolescence, biometric privacy, false acceptance, false rejection, route failure, virtual-camera/API injection, capture-channel compromise, adversarial probing, and scope inflation.

#### 6.1.2 Budgeting and Resource Identification

The Week 7 report contains a planned USD 260–540 GPU budget. Replace or supplement it with actual compute/storage/tool use. Distinguish paid resources, free Kaggle/university resources, personal devices, personnel time, and estimated production serving cost.

#### 6.1.3 Economic Analysis and Financial Prospecting

Avoid unsupported fraud-loss percentages. Use cited market evidence and a transparent cost model: development compute, on-device savings, server escalation rate, reviewer cost, false-acceptance loss, and false-rejection/user-abandonment cost.

#### 6.1.4 Sustainability in Business and Commercialisation

Describe a realistic path: research validation → security review → partner pilot → monitored shadow deployment → limited rollout → periodic model updates. Identify ownership for model maintenance, incident response, and compliance.

### 6.2 Individual and Teamwork

Earlier assigned roles are not enough; this section needs verified actual contributions from each member. Git history is supporting evidence but is not a complete contribution record. Obtain each member's implementation, experiment, documentation, presentation, integration, review, leadership, and deadline contributions.

#### Participation and Contribution

Give each member's verified role, concrete outputs, participation in technical decisions, and whether assigned work was completed on schedule.

#### Collaboration and Conflict Resolution

Describe the actual collaboration process, code/experiment handoffs, review practices, disagreements or blockers, and how the team resolved them.

#### Leadership and Direction

Identify how technical direction was set, how competing views were evaluated, how the team responded to failed experiments, and who coordinated integration and reporting.

#### Multidisciplinary Engagement

Document real engagement with the industry partner, supervisor, domain/security experts, users, or other disciplines. Do not imply consultations that did not occur.

### 6.3 Impact on Society

Positive impacts: reduced identity fraud, increased trust, scalable onboarding, and potential financial inclusion.

Negative impacts: exclusion through false rejection, surveillance/misuse of biometrics, opaque decisions, accessibility barriers, account-opening friction, and workforce changes for reviewers.

For each impact, identify affected people and the design mitigation.

### 6.4 Environmental Impact and Life Cycle Sustainability

Cover data preparation and repeated GPU training, cloud storage, server inference, mobile battery use, model updates, data retirement, and hardware lifecycle. Mitigations include lightweight screening, selective escalation, model compression, experiment reuse/caching, retention limits, and carbon/energy reporting where measurable.

### 6.5 Ethics

Ethics should be treated as a design constraint throughout the report, not as a generic closing discussion. Build an **ethical risk--control--evidence matrix** with columns for stakeholder, possible harm, likelihood/severity, design control, evidence available, and remaining gap. At minimum, cover:

- Collection and processing of non-revocable facial biometric data.
- Informed consent, purpose limitation, retention, deletion, and secondary-use prohibition.
- False acceptance as a fraud/security harm and false rejection as an exclusion/financial-access harm.
- Threshold ethics: `tau_pass` and `tau_attack` distribute fraud risk, false-rejection burden, server cost, and waiting time differently. Their selection requires documented ownership, subgroup evaluation, and change control rather than a convenience value.
- Demographic, device-quality, lighting, disability, age, and cultural disparities.
- Selective-escalation bias: a confidence-based cascade may send particular devices or demographic groups to the slower/more invasive server path more frequently, so escalation rates and outcomes should be audited by subgroup where lawful and supported by consented data.
- Transparency about automated decisions without revealing attack-enabling details.
- A retry, appeal, and meaningful human-review route for adverse decisions.
- Security of data in transit, temporary files, model/API access, logs, and stored artifacts. Escalation should transmit the minimum necessary frames/features, with explicit retention and deletion behavior.
- Dual-use risk: detector code, thresholds, and failure analyses can also help attackers probe the system.
- Dataset provenance, consent, licensing, subject dignity, and whether public availability actually permits the intended use.
- Reviewer privacy, working conditions, consistency, accountability, and automation bias if human review is introduced; reviewers need usable evidence and authority to overturn a model rather than merely confirm it.
- Energy/resource costs of repeated training and escalating every sample to a server.

#### Equity and Inclusivity

Discuss skin tone, age, gender presentation, disability, facial differences, religious/cultural face coverings, camera quality, language, connectivity, and low-end devices. Treat equal aggregate accuracy as insufficient: report subgroup FAR and FRR with sample counts and uncertainty where reliable labels exist. Asian-Fakes results cannot establish fairness and should be presented as evidence that broader validation is needed. Users who cannot complete face verification need an accessible alternative rather than repeated automated rejection.

#### Accountability and Personal Responsibility

Define who owns model errors, threshold changes, incident review, user notification, appeals, data deletion, dataset/model releases, and post-deployment monitoring. High-stakes account access should not rely on an unexplained model score with no recourse. Document model/version provenance so a disputed decision can be reconstructed.

#### Proper Use of Intellectual Property

Inventory and cite:

- FaceForensics++, Celeb-DF-v2, LCC-FASD, ROSE-Youtu, and Asian/SBI source datasets with their licenses/terms.
- Xception pretrained weights.
- G2V2Former, GD-FAS, STDL-FacePAD, and any copied/adapted implementations.
- Flutter/PyTorch/OpenCV and other third-party libraries.
- Any reproduced paper figures.
- Generative-AI assistance.

The repository README says MIT, but no tracked `LICENSE` file is present; resolve this before making a formal licensing claim.

#### Professionalism and Ethical Codes

Connect ACM/IEEE/IEB principles to specific choices: privacy by design, data minimization, cautious claims, transparent limitations, human appeal, auditability, nondiscrimination, security testing, and protection of the public interest. Explicitly reject misleading claims of production readiness, certification, demographic fairness, or universal deepfake coverage when the experiments do not support them.

## Chapter 7 — Conclusion

### 7.1 Conclusion and Future Work

Summarize achievement against each numbered objective. The conclusion should combine the project's findings:

- Lightweight temporal modeling is promising for physical PAD and can be integrated into a mobile prototype.
- G2V2Former demonstrates learnable temporal/landmark evidence but weak physical-PAD-to-deepfake transfer and training sensitivity.
- GD-FAS provides a much stronger LCC-FASD baseline and better retention/transfer after Celeb-DF-v2 fine-tuning, yet it still does not solve cross-domain deepfake generalization.
- Asian-Fakes results expose remaining transfer/fairness uncertainty rather than demonstrating demographic robustness.
- Manipulation-specific routing improves substantially over a universal Xception within FF++, adding a useful later result without completing the broader liveness-verification problem.
- The combined prototype is not yet proven against unseen generators, real financial traffic, broad demographics, or production security requirements.

Prioritized future work:

1. Establish one common, leakage-safe evaluation suite for MobileNetV3, G2V2Former, GD-FAS, and routed specialists.
2. Add held-out and cross-dataset testing, unseen generators, open-set attacks, and repeated seeds with uncertainty estimates.
3. Improve temporal modeling, landmark reliability, frequency/blending evidence, and source-domain retention during deepfake fine-tuning.
4. Add video-level aggregation to the manipulation-specific expert branch and compare hard, soft, and top-k routing.
5. Calibrate probabilities, select confidence-band thresholds using asymmetric security and exclusion costs, and measure the accuracy--escalation--latency trade-off.
6. Complete and secure the capture-to-server path: add feasible sensor/session provenance and virtual-camera/injection controls, choose and validate the Layer-2 selection/fusion policy, then add authentication, encryption, monitoring, rollback, and privacy-preserving retention.
7. Evaluate fairness with consented, properly documented demographic data, subgroup FAR/FRR, confidence intervals, and accessible fallback paths.
8. Measure real-device/model-server storage, RAM, latency, battery/energy, and throughput; then compress or distill where needed.
9. Test compression, resizing, blur, camera recapture, adversarial post-processing, replay, injection, and mixed physical--digital attacks.
10. Design and test an accountable hard-case human-review/appeal workflow, then conduct an industry-supervised pilot only after privacy, security, legal, and ethical requirements are independently reviewed.

### 7.2 Continuous Engagement and Self-directed Learning

Use concrete evidence:

- Learning and reproducing graph-guided video transformers.
- Debugging numerical instability in attention guidance.
- Designing video/group-disjoint dataset protocols.
- Exporting a temporal model to PyTorch Lite with an explicit tensor contract.
- Comparing CNN and gradient-boosted router heads.
- Learning the distinction between PAD and digital deepfake domains through experiments.

## 6. Required figures and tables

Minimum recommended visuals:

1. Physical-versus-digital attack taxonomy with separate delivery-path, manipulation-family, and evidence-type axes.
2. Project evolution/timeline.
3. As-built component architecture.
4. Main two-layer edge--server--review decision pipeline, with confidence bands and every edge labeled as implemented or proposed.
5. Temporal hierarchy figure comparing Layer-1 mean aggregation with Layer-2 explicit visual/landmark temporal interaction.
6. Layer-1 MobileNetV3 detail: 24-frame Flutter capture, shared per-frame feature extractor, temporal mean, logits, softmax confidence, and proposed routing policy.
7. Layer-2 candidate-evidence diagram: G2V2Former, GD-FAS, and universal/routed Xception lanes converging at a proposed calibration/fusion and hard-case review block.
8. G2V2Former visual--landmark architecture.
9. G2V2Former epoch-wise LCC-FASD/Celeb-DF-v2 domain gap.
10. G2V2Former versus GD-FAS common-protocol comparison.
11. Asian-Fakes transfer comparison with an explicit fairness limitation caption.
12. FF++ extraction and group-disjoint split.
13. Embedding-conditioned specialist-routing data flow: frame -> 2,048-dimensional embedding -> `P(best expert | embedding)` -> hard expert selection -> binary fake probability. Show no `original` route in the intended figure.
14. A clearly labeled current-versus-intended router diagram: current six-way original/method classifier versus intended five-expert selector.
15. Specialist cross-method heatmap and router confusion matrix; do not reuse the six-way matrix as evidence for the five-way router.
16. Universal versus routed-ensemble metric comparison, labeled with the exact router version.
17. If implemented: reliability diagram and confidence/escalation trade-off curve; otherwise list these as required future evaluation, not results.
18. Actual project Gantt chart.

Minimum recommended tables:

1. Attack taxonomy and threat assumptions.
2. Literature synthesis and research gap.
3. Stakeholders and expectations.
4. Requirements traceability matrix.
5. Standards/regulations and design response.
6. Alternative-solution decision matrix.
7. Pipeline component, layer, temporal mechanism, role, and implementation status.
8. Dataset summary and split protocol.
9. Model/training configuration.
10. G2V2Former architecture/training configuration and results.
11. GD-FAS protocol deviations and results.
12. Cross-domain G2V2Former/GD-FAS comparison.
13. Universal/specialist/meta-router results with current and intended formulations separated.
14. Five manipulation types, generation family, expected artifact differences, specialist, and dataset coverage.
15. Per-method specialist/universal/ensemble comparison.
16. Objectives/requirements versus final status.
17. Engineering risks and mitigations.
18. Ethical risk--control--evidence matrix.
19. Budget/resource breakdown.
20. Verified team contributions.
21. Third-party assets, licenses, and attribution.

## 7. Claims that must be avoided or qualified

- Do not say the complete system is deployed at Pathao Pay.
- Do not imply that Pathao supplied training/evaluation data, compute, grants, or sustained technical assistance; its documented role was providing the project problem and early context.
- Do not describe public dataset or open-source authors as project sponsors or direct collaborators unless they actually provided assistance.
- Do not say the system is ISO certified or legally compliant without formal evidence.
- Do not treat vendor marketing as independent performance or compliance evidence. In particular, do not copy the ARSA article's standards list uncritically: ISO 45001 concerns occupational health and safety, whereas biometric presentation-attack testing belongs to the ISO/IEC 30107 family.
- Do not present NIST SP 800-63A-4 as binding Bangladesh law; use it as authoritative security guidance and separately establish which Bangladesh requirements apply.
- Do not call FF++ validation performance cross-dataset generalization.
- Do not claim demographic fairness from Asian-Fakes results.
- Do not claim the current app uses the G2V2Former server; the call is disabled.
- Do not describe the current prototype as an operating two-layer cascade: confidence-band routing, Layer-2 selection/fusion, and human review are target-state designs.
- Do not call the current Flutter softmax output calibrated confidence or present `tau_pass`/`tau_attack` as chosen values until calibration and operating-point selection are performed.
- Do not describe GD-FAS or the evaluated Xception experts as temporal models. They are frame-based spatial/domain-specialized complements; only a future video-level aggregation would combine their evidence across frames.
- Do not imply that a human reviewer is currently available, or that model disagreement is already handed off to one.
- Do not use “MoE” as the primary name for the final routing method. Use **embedding-conditioned meta-routed specialist ensemble** or **hard specialist-routing model** and define the discrete routing equation.
- Do not say the current notebooks implement `P(best expert | embedding)`: they currently learn a six-way `original`/manipulation classifier. Do not report the current 81.12% routing score or routed binary metrics as five-expert meta-router results.
- Do not retain an `original` route or `1 - P(original)` fallback in the intended mathematical formulation. Every frame must be assigned to one of the five binary specialists.
- Do not equate a manipulation-method target with a best-expert target without showing that the matched specialist is actually the oracle best model for that sample.
- Do not use accuracy alone on the 10,000-real/50,000-fake overall validation set.
- Do not imply the five expert checkpoints or server checkpoint are versioned in this repository when they are external/not tracked.
- Do not use the latest report's 21.71% best LCC-FASD HTER until it is reconciled with the current notebook outputs (24.07% in one run and 22.38% in the common-protocol experiment).
- Do not present planned market, budget, latency, availability, or accuracy targets as measured achievements.

## 8. Evidence gaps to resolve before drafting the report

### Administrative

- Final confirmation of the provisional title, **Leveraging Temporal Information for Robust Liveness Verification**.
- Session, submission date, supervisor details.
- Confirmed spelling of all names.
- Exact wording for the supervisor's contribution, including that the embedding-conditioned specialist-routing idea was the supervisor's.
- Name/title of the Pathao contact if required, limited to the initial project brief and early context.
- Course policy for generative-AI disclosure.

### Technical

- Reconcile the G2V2Former 21.71%, 22.38%, and 24.07% best-HTER values and identify the final authoritative run.
- Freeze the exact G2V2Former and GD-FAS checkpoints, dataset subsets, thresholds, and result CSVs used in the common-protocol table.
- Verify complete bibliographic metadata and implementation attribution for G2V2Former and GD-FAS.
- Trace the LinkedIn post's injection-attack percentages to the original iProov threat report, record its vendor-observation scope, and use NIST/ENISA for the core injection threat model. Treat ARSA as practitioner/vendor context rather than validation of this project's controls.
- Freeze a three-axis attack taxonomy—delivery path, manipulation family, and evidence type—and ensure every dataset/result is mapped to the attacks it actually covers.
- Decide whether virtual-camera/injection resistance remains an explicit unimplemented requirement or whether any capture-integrity control can be prototyped and tested before submission.
- Reconcile the MobileNetV3 temporal configurations: the current training script uses K=10, while full-video inference, export, and Flutter use K=24. Record the checkpoint hash, saved training `num_frames`, export provenance, and whether changing K at inference is validated.
- Rerun/evaluate the exact K=24 MobileNetV3 checkpoint bundled with the Flutter app; the repository has its model contract but no committed result CSV.
- Run the mobile acceptance test using one shared video in Python and Flutter.
- Calibrate the Layer-1 score on a leakage-safe validation set; report reliability/ECE or Brier score, choose `tau_pass` and `tau_attack` from explicit FAR/FRR/cost criteria, and measure the fraction sent to Layer 2.
- Decide which Layer-2 model or combination is actually proposed for each threat type. If fusion is claimed, define score normalization, missing-model behavior, conflict handling, and validate the fusion rather than averaging incomparable raw scores.
- Evaluate the whole cascade on video/group-disjoint data, including quality-gate failures, conditional performance on escalated samples, end-to-end FAR/FRR, latency, bandwidth, privacy exposure, and failure fallback.
- If GD-FAS or Xception contributes video-level evidence, implement and compare frame sampling and score/logit aggregation; do not relabel frame models as temporal architectures.
- Specify the proposed human-review trigger, information shown, reviewer authority, appeal path, retention/access controls, and audit log. Keep it explicitly future work unless a functioning workflow is built and tested.
- Measure real-device latency, RAM, model load time, and battery/energy if mobile-performance claims will be made.
- Redesign the router output from six classes to five experts and remove the `original` fallback from both CNN and XGBoost paths.
- Define leakage-safe best-expert labels using out-of-fold specialist probabilities/losses; document tie handling and how genuine frames receive expert targets. If method labels are retained instead, rename the target honestly as manipulation-method routing.
- Rerun the full routed evaluation and replace all current six-way metrics/plots before claiming the intended embedding-conditioned meta-router is implemented.
- Add cross-dataset and unseen-method evaluation for the specialist-routing model, including an explicit policy for an unseen manipulation that matches none of the five training routes.
- Add a true held-out test set or nested validation protocol for specialist routing.
- Calculate calibrated FAR, FRR, EER/HTER, routing regret, confidence intervals, and repeated-seed variance for the final specialist-routing model.
- Preserve versioned model checkpoints/configuration hashes or explain their external storage.
- Verify whether the FF++ usage license permits the intended reporting/distribution.

### Management, impact, and evidence

- Actual contribution record for all five members.
- Actual timeline versus planned timeline.
- Actual spending and computing-resource use.
- State transparently that sustained primary user/partner research and private Pathao data were not available beyond the initial project framing; use cited secondary evidence where appropriate.
- Record explicitly that no dataset grant or project grant was received.
- Current standards, laws, and Bangladesh Bank requirements from authoritative sources.
- Dataset, model, code, and figure license inventory.
- Complete bibliography entries and citation verification.

## 9. Recommended drafting sequence

1. Resolve the evidence gaps and freeze final result tables.
2. Copy/adapt the LaTeX skeleton into `final report/`, leaving the reference template ignored.
3. Build `references.bib` from verified primary sources.
4. Draft Chapters 1, 3, and 4 to lock scope, requirements, and architecture.
5. Draft Chapter 5 directly from frozen artifacts and plots.
6. Draft the literature review around the experimental questions.
7. Collect team, budget, timeline, impact, and ethics evidence for Chapter 6.
8. Write conclusions against objective IDs.
9. Write the abstract last.
10. Perform a final rubric audit, citation/license audit, numerical consistency audit, and compile check.

## 10. Current recommended report emphasis

Allocate the most space to the combined research contributions and evidence:

- Chapters 1–3: approximately 20–25%.
- Chapter 4: approximately 20–25%.
- Chapter 5: approximately 30–35%.
- Chapters 6–7: approximately 20–25%.

Within the technical design/evaluation material, a reasonable balance is:

- G2V2Former, GD-FAS, and their common cross-domain analysis: approximately 40–45%.
- Lightweight/mobile temporal work and integration: approximately 20–25%.
- Embedding-conditioned specialist routing and its router-head ablation: approximately 20–25%.
- Cross-cutting synthesis of limitations, safety, fairness, and deployment implications: approximately 10–15%.

The report should not read as a collection of unrelated models, and it should not culminate rhetorically in specialist routing as though all earlier work were only preparation for it. It should follow the real chronology: a broad secure-liveness problem, layered system design, lightweight/mobile modeling, temporal G2V2Former investigation, GD-FAS domain-generalization comparison, integration work, and finally embedding-conditioned specialist routing as an additional result. G2V2Former, GD-FAS, the cross-domain findings, the mobile prototype, and the ethical analysis should receive substantial independent attention.

## 11. Proofread current-status snapshot

Use this table as the final guard against turning intended design into completed work:

| Item | Status after repository audit | Permitted report wording |
| --- | --- | --- |
| Flutter MobileNetV3 Layer 1 | Implemented locally for one consecutive K=24 clip with a fixed 0.5 softmax boundary | “Integrated mobile prototype”; not “calibrated cascade” |
| K=10 training versus K=24 export | Unreconciled provenance/evaluation issue | State the mismatch and verify before reporting the shipped artifact's performance |
| G2V2Former temporal Layer 2 | Trained/evaluated; FastAPI demonstrated separately | “Experimental server-side model”; not “connected second layer” |
| GD-FAS | Evaluated as an image-based domain-generalization comparison | “Comparison/candidate server evidence”; not “temporal model” or “deployed service” |
| Xception specialists and universal model | Evaluated on FF++ C23 frames with group-disjoint validation | Report as in-domain, frame-level evidence only |
| Current CNN and XGBoost routers | Six-way `original` plus five-method classifiers | Report current numbers only as the previous six-way formulation |
| Intended meta-router | Five expert outputs estimating `P(best expert | embedding)` with no `original` route | Proposed until best-expert targets are defined and both router heads and final metrics are rerun |
| Confidence-band mobile-to-server escalation | Designed in this plan; HTTP call disabled | Target architecture/future integration only |
| Capture-channel/injection defense | Threat requirement identified; no sensor attestation or virtual-camera defense found | Unimplemented requirement and future work |
| Score fusion across G2V2Former, GD-FAS, and Xception | No integrated/calibrated fusion found | Candidate design only |
| Human review/appeal workflow | No implementation found | Proposed safeguard only |
| Pathao involvement | Initial problem and early context only; no private data, grant, or sustained technical support documented | Acknowledge accurately without implying sponsorship or deployment |

Before submission, repeat this audit against the final commit, model artifacts, and result files so the report's tense, captions, diagrams, and abstract all match the evidence then available.
