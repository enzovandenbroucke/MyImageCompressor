# Validation locale — 2 octobre 2026

Environnement : Windows 11 x64, OCaml 4.14.0, compilation bytecode. Le
compilateur portable et les bibliothèques de tracé ont été téléchargés hors du
dépôt ; aucune installation globale n'a été faite.

- Compilation effective de tous les modules, de l'interface et des tests.
- 482 168 assertions OCaml réussies, incluant les contrôles par pixel. Les
  scénarios comprennent DFT/FFT, DCT directe/FFT, DCT/IDCT, amplitudes signées,
  chaînes de blocs, dimensions 1×1 à 480×240 et fichiers incomplets.
- Vérification indépendante via Pillow et Python du PSNR RGB, des dimensions,
  de la taille réellement écrite, des longueurs de flux et des formules bpp et
  rapport de compression, sur plusieurs qualités.
- Conversion PNG vers PPM contrôlée par comparaison des octets RGB et des
  empreintes, avec dimensions impaires. Conversion également exécutée sur les
  fichiers DIV2K 0801 à 0803 ; seule l'image 0801 a été benchmarkée.
- Création de la comparaison visuelle à partir de fichiers `.ojpg` écrits puis
  relus, et inspection de l'illustration obtenue.
- Benchmark photographique complet sur 0801 aux qualités 10, 50 et 90,
  dimensions originales 2040×1356, avec un échauffement et un passage mesuré.
- Comparaisons DFT/FFT et DCT directe/FFT exécutées ; erreur numérique mesurée.
- Graphique des mesures réellement exécutées, inspecté visuellement.

Les mesures de transformées évitent les divisions par un temps CPU nul en
répétant les lots durant au moins 0,2 seconde et en utilisant le temps écoulé
pour le rapport de vitesse. Les temps CPU sont aussi conservés.

La CI GitHub est configurée mais n'a pas été exécutée sur GitHub. La compilation
native, OCaml 5.3 et le benchmark sur l'ensemble des 100 images restent à vérifier
dans leurs environnements respectifs. Aucun chiffre de comparaison contre un
encodeur JPEG de production n'est revendiqué.

## Ajustement du benchmark

Le mode par défaut est désormais un passage mesuré sans échauffement. La
compilation et les vérifications d'intégration ont été relancées : les métriques
d'image sont identiques avec ou sans échauffement, les paramètres sont enregistrés
dans le CSV et le JSON, et les valeurs négatives d'échauffement sont refusées.
Les résultats historiques de `benchmarks/` conservent leurs conditions d'origine.

## Illustration photographique

La photo DIV2K 0809 est traitée à sa résolution originale 2040×1356 aux qualités
10, 50 et 90. La conversion PNG/PPM conserve exactement les échantillons RGB.
Chaque reconstruction provient d'un fichier `.ojpg` écrit puis relu, avec un
seul encodage et décodage par qualité. Les métriques du fichier et le PSNR sont
calculés à partir de ces mêmes sorties. Les aperçus sont réduits uniquement pour
l'affichage et un détail identique est agrandi pour les quatre variantes.
