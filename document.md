
Contents
1 Introduction
2 LiteratureSurvey
3 Objectives
4 Methodology
5 Phase-wisePlan
6 GanttChart
7 Conclusion
8 References

Introduction
Background
• PTZcamerasinrestrictedindoorfacilities
cannotobserveeventsoutsidetheirfieldof
view.
• PIRsensorsonlyindicatemotionpresence,
lackingtheprecisedirectionneededfor
accuratecameraorientation.
• Vision-basedmotiondetectionprovidesbetter
localizationbutrequirescontinuousimage
processingandhighercomputationalpower.

Proposed Contribution
• Integrate3DDirectionofArrival(DOA)estimationtofindtheAzimuth
andElevationofdominantacousticevents.
• EnablePTZcamerastorapidlyandautomaticallyorienttowardthe
soundsource.
• Implementdomainadaptationtoensurerobustperformanceacross
differenttargetindoorenvironments.
• Complementexistingsurveillancebyprovidingprecisedirectional
awareness,reducingrelianceonintensivevision-basedmethods.

Objectives
Primary Objective
Developareal-time,edge-embeddedsystemcapableoflocalizing
abnormalacousticeventstoautomaticallyguidesurveillancecamerasin
restrictedindoorfacilities.
SpecificObjectives
• SpatialEstimation: Compute3DDirectionofArrival(Azimuth&
Elevation).
• DomainAdaptation: Adaptthelocalizationmodelseamlesslyacross
varyingindoortargetareas.
• CameraIntegration: AutomaticallyorientaPTZcameratowardthe
dominantsoundsource.
• SystemUtility: Provideearlyfaultlocalizationtoenhancesafetyand
reducemanualinspection.

Methodology
flowchart LR

    A[Audio Source] --> B[Microphone Array]

    B --> C["Audio Acquisition<br/>and noise filtering<br/>using Band Pass<br/>filter, VAD"]

    C --> D

    subgraph D["Feature Extraction"]
        D1["GCC-PHAT Delay"]
        D2["MUSIC Spectrum"]
        D3["ILD"]
        D4["RMS"]
        D5["FFT Features"]
        D6["Spectral Entropy"]
    end

    D --> E["Domain Adaptation<br/>(CORAL / Stats Matching)"]

    E --> F["Classical ML<br/>Classifier<br/>(RF / SVM)"]

    F --> G["Estimated<br/>DOA Angle"]


Methodology - System Pipeline
• HardwareUsed: RaspberryPipairedwitha4-to-8microphonearray
foracousticcaptureandedgeprocessing.
• AudioAcquisition&Filtration:Appliesband-passfilteringandVoice
ActivityDetection(VAD)toisolatetargeteventsfromtherawsignals.
• FeatureExtraction: Computesvitalspatialcuesincludingtime
delaysviaGeneralizedCross-CorrelationwithPhaseTransform
(GCC-PHAT),spectralpeaksusingMultipleSignalClassification
(MUSIC),andInterauralLevelDifferences(ILD).
• DomainAdaptation:Alignsfeaturedistributions(e.g.,viaCorrelation
Alignment-CORAL)betweentraininganddeploymentfor
cross-domainrobustness.
• ClassicalMLClassifier: Predictssounddirectionbyfeedingadapted
featuresintotrainedmodelslikeRandomForest(RF)orSupport
VectorMachine(SVM).
• EstimatedDOAAngle: Outputs3DDirectionofArrival(Azimuthand
Elevation)toautomaticallyorientthePTZcameratowardthe
anomaly.

Conclusion
ExpectedOutcomes
• Real-timeembedded3DDirectionofArrival(DOA)estimationusinga
microphonearray.
• AccurateestimationoftheAzimuthandElevationofdominant
acousticevents.
• Robustcross-environmentacousticlocalizationusingdomain
adaptation.
• AutomaticPTZcameraguidancetowardthedetectedacousticevent.
• Improvedsituationalawarenessinrestrictedindoorfacilitiesby
complementingexistingsurveillancesystems.

References I
R.O.Schmidt(1986)
MultipleEmitterLocationandSignalParameterEstimation
IEEETransactionsonAntennasandPropagation,vol.34,no.3,pp.276-280.
S.Lokhande,A.Malarkodi,G.Latha,andS.Srinivasan(2025)
Autonomousdetection,localizationandtrackingofshipsbyunderwateracousticsensingusing
vectorsensorarray
AppliedOceanResearch,vol.154,p.104389.
R.Li,M.Li,Q.Li,andJ.Li(2025)
Cross-DomainUnderwaterSoundSourceLocalizationAlgorithmBasedonBinauralMatrixand
MutualInformationConstraintLoss
IEEEJournalofOceanicEngineering,vol.50,no.2,pp.1419-1428.
A.I.Mezza,E.A.P.Habets,M.Mu¨ller,andA.Sarti(2020)
UnsupervisedDomainAdaptationforAcousticSceneClassificationUsingBand-WiseStatistics
Matching
EUSIPCO2020.
M.Hameed,M.Rai,A.Srivastava,andM.Fathima(2025)
DesignandImplementationofAcousticGunshotDetectionUsingMachineLearningandSource
LocalizationwithDirectionofArrivalAlgorithm
2025IEEEInternationalConferenceforWomeninInnovation,Technology&Entrepreneurship(ICWITE).
L.Li,K.Lian,J.Fu,P.Zhu,Z.Hu,andC.Guo(2020)
AcousticEnhancedCameraTrackingSystemBasedonSmall-ApertureMEMSMicrophoneArray
IEEEAccess,vol.8,pp.215827-215839.
