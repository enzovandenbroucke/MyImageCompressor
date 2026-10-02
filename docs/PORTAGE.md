# Démarche de préparation du dépôt

La base retenue est exclusivement la version `final/FFT.ml`. Les fichiers
d'origine n'ont pas été modifiés. Ce dépôt est une extraction et une adaptation,
pas une nouvelle implémentation indépendante du travail de TIPE.

## Ce qui est conservé

- FFT récursive par séparation des coefficients pairs et impairs.
- Construction de la DCT via une FFT de taille 2N, variante 4N, IDCT.
- Coefficients de conversion RGB/YCbCr et moyenne des chrominances sur 2×2.
- Tables de quantification, règle de qualité, tables Huffman fixes.
- Orientation du zigzag, prédiction différentielle DC et principe RLE/Huffman.
- DFT naïve et sommes de cosinus comme références explicatives.

Les noms historiques de la partie numérique restent présents dans `dct.ml`,
pour faciliter la comparaison avec le TIPE. Les mesures de transformées sont
accessibles par une commande distincte. Les impressions de debug à chaque
pixel, anciens chemins absolus, matrices d'essai inutilisées et fonctions de
bruit sans lien avec le codec ont été retirés du chemin d'exécution.

## Corrections et choix

**Dimensions.** L'ancien code arrondissait vers le bas à un multiple de 8,
puis sous-échantillonnait les chrominances. Une image dont les dimensions
n'étaient pas multiples de 16 pouvait perdre des pixels ou provoquer un accès
hors tableau. La nouvelle version prolonge les bords au multiple de 16 supérieur,
mémorise les dimensions initiales et retire le prolongement après reconstruction.
Cela fonctionne aussi sur une image 1×1 et une image rectangulaire 480×240.

**Bits et fichiers.** `final/FFT.ml` ne fournit pas de conteneur compressé
autonome avec son lecteur. L'ancienne fonction d'écriture problématique
identifiée dans une autre version n'est donc pas transposée. Un petit format
`OJPG` versionné a été ajouté avec qualité, dimensions et longueurs exactes des
trois flux. Le dernier octet incomplet est conservé, complété par des zéros et
relu sans traiter ces zéros comme des données. Le format est documenté et
explicitement distinct de JPEG/JFIF et PPM.

**Mémoire et récursion.** Le flux complet n'est plus une liste de caractères
`'0'`/`'1'`. Les bits sont écrits directement dans un tampon d'octets, bloc après
bloc, avec des boucles pour parcourir l'image. Cela supprime les longues
concaténations et la récursion proportionnelle au nombre de blocs. Les blocs
transformés ne sont pas tous conservés simultanément. Les plans couleur restent
en mémoire : ce portage n'est pas un codec entièrement en streaming.

**Huffman.** Les arbres sont construits à partir des tables d'encodage, avec
vérification des collisions de préfixes. Les branches absentes restent invalides,
au lieu de devenir des feuilles par défaut dans un arbre complet de profondeur
16. Cela évite aussi de stocker des dizaines de milliers de nœuds inutiles.
Les blocs denses consomment explicitement leur EOB et les séquences ZRL sont
bornées à leur bloc. Le choix EOB systématique est documenté dans le format.

**Fichiers PPM.** Lecture et écriture binaires, fermeture des fichiers même en
cas d'erreur, prise en charge des commentaires, espaces, tabulations et CRLF
dans les en-têtes usuels, validation de maxval=255 et des fichiers tronqués.
Les octets de pixels valant 10, 13 ou 32 ne sont pas confondus avec des espaces
à éliminer après l'en-tête.

**Qualité.** La qualité est bornée à 1..100 avant toute division ; zéro est
refusé. Les quantificateurs restent au minimum à 1, comme dans le code original.
Une qualité de 100 ne rend pas la chaîne sans perte.

**Mesures.** Le PSNR accumule une somme flottante et vérifie les dimensions.
Les rapports comptent séparément les bits valides et le fichier complet ; le
dénominateur reste l'image originale, même lorsqu'un prolongement est utilisé.
Les temps CPU et les temps écoulés sont distingués et rapportés au volume RGB
non compressé, en Mo décimaux. Le benchmark effectue par défaut un seul passage
mesuré sans échauffement, en excluant les lectures/écritures de fichiers. Pour
une étude des temps, `--warmup 1 --repeat 3` active un échauffement puis la
médiane de trois passages. Les paramètres sont conservés dans le CSV et le JSON.

**Conversion PNG.** Aucun décodeur PNG n'a été identifié dans les sources
historiques examinées. Le nouveau script utilise explicitement Pillow et
préserve dimensions et valeurs RGB pour les PNG RGB usuels. Il produit un
manifeste avec empreintes ; cela ne prouve pas quel logiciel a été employé
pendant le TIPE.

**Référence DCT.** La formule naïve est conservée comme référence, avec une
normalisation en fonction de N. La division fixe par 4 de l'ancien code était
correcte à taille 8, mais ne permettait pas une comparaison générale sur toutes
les tailles. Les comparaisons portent sur la tolérance numérique et non sur
l'égalité exacte des flottants.

## Validation et portée

Les tests couvrent les transformées, amplitudes signées, chaînes de blocs
Huffman, blocs creux/denses, dimensions petites/impaires/rectangulaires, valeurs
RGB, PPM, aller-retour des flux via un fichier et fichiers tronqués.
Le contrôle de chaque échantillon RGB explique le grand nombre d'assertions :
il ne s'agit pas de centaines de milliers de scénarios indépendants.

La compilation et l'exécution locales utilisent un compilateur OCaml 4.14.0
portable, extrait hors du dépôt, sans installation globale. La CI est préparée
pour OCaml 4.14 et 5.3 sous Linux ; son exécution GitHub n'est pas encore vérifiée.
Les mesures DIV2K livrées portent sur une seule image, à taille originale, avec
un passage mesuré après échauffement. Le jeu complet n'a pas été benchmarké.

Les notes de validation et les fichiers `benchmarks/` décrivent précisément les
résultats exécutés. Les mesures bytecode servent de point de départ ; pour
valoriser la performance, refaire l'expérience en compilation native avec
plusieurs répétitions et une machine documentée.

## Avant publication

Le dossier est prévu pour être la racine du dépôt GitHub. Les données lourdes
et les sorties temporaires sont ignorées. Le README présente en premier une
comparaison issue de la photo DIV2K 0809, avec attribution séparée, puis
l'illustration synthétique. Le jeu complet n'est pas inclus. Il reste à choisir une licence logicielle
et à créer le dépôt distant. Aucun compte ni dépôt GitHub n'a été modifié.
