# This is (hopefully) the complete code that I used for analysis of the Cyprinella microbiome project. I also have more failed/unused analysis backed up in other files
# Contents include: Qiime, Permanova, NMDS, Mantel tests, Alpha diversity Boxplots, Linear models, Network analysis, Map
# Author: Will Hanson-Regan July 2023

### Qiime ######

  ## credit to Francesca Leasi for all of this, I basically just made slight moderations to make it specific to my data.
  ## This was done in the SimCenter Epyc cluster, accessed with command prompt. 
  ## These codes are specific to the 16S, the 18S process was nearly identical except for less stringent cutoffs
  ## qiime2 is just one of the many tools you can use. You can use R or many other developed tools. You can find the tutorial here https://docs.qiime2.org/2023.2/tutorials/moving-pictures/
  ## they update it very often so this link may not work in just a few weeks, but look for "moving-pictures".
  ## you got your sequences in a .gz file, which is a compressed fastq, which means DNA sequences + information about sequence quality. Every file includes either all the F or the R for each sample
  ## you can open one using Geneious or another software and get an idea of how many genetic reads you have for each samples...then realize it is impossible to use Geneioius...
  
  #STEP 1: IMPORT READS INTO THE SERVER. download your reads on your computer. In my case, I downloaded the reads into a folder named "will" located on the desktop. Therefore create a folder in your server account:
  scp Microbiome/Microbiome_results_16s/*.gz whansonregan@epyc.simcenter.utc.edu:/home/whansonregan/microbiome/16s
  
  #check if all your reads are there by asking how many .gz files are in raw_reads
  cd raw_reads
  ls -1 *.gz | wc -l
  
  #STEP 2: ACTIVATE QIIME2. qiime2 should be installed in the Epyc cluster.
  module load anaconda 
  #check the last version, they update the software very often. I keep asking Corbin to update it.
  conda info --envs
  #choose the last version
  source activate qiime2-2022.11
  
  #STEP 3: PAIR DEMULTIPLEXED READS we are in the directory will_fernando. We want to import data from the raw_reads directory to an artifact zip file of Qiime2 having extension .qza. Because it can be a relatively long process
  #the 'nohup' and '&' allow you to close your computer and let it run but itself. 
  nohup qiime tools import --type 'SampleData[PairedEndSequencesWithQuality]' --input-path 16s/ --input-format CasavaOneEightSingleLanePerSampleDirFmt --output-path demux-paired-end-16s.qza &
    #To check if it is still running, you can type 
    jobs
  #if there is some mistake, it will show up as EXIT, then check what the problem was by typing
  less nohup
  
  #STEP 4 CHECK THE QUALITY. you can start visualizing your data. These visualizations are important for data filtering. First, convert the .qza file into a .qzv file.
  qiime demux summarize --i-data demux-paired-end-16s.qza --o-visualization demux-paired-16s.qzv 
  #export your .qzv file in your computer. you need to open another bash window without logging it
  scp -r whansonregan@epyc.simcenter.utc.edu:/home/whansonregan/microbiome/demux-paired-16s.qzv Microbiome
  #then you can drag your demux-paired.qzv file into this website https://view.qiime2.org/ and explore it. You want to check both pages, the interactive quality plot gives you an idea of the sequence quality
  
  #STEP 5: DENOISING AND FILTERING.DADA2 pipeline
  qiime demux summarize --i-data single-end.qza --o-visualization single_end.qzv 
  nohup qiime dada2 denoise-single --i-demultiplexed-seqs single-end.qza --o-table sv-table_f100_247 --o-representative-sequences rep-seqs_f100_247  --p-n-threads 30 --p-trim-left 100 --p-trunc-len 247 &
    #check the output
    qiime metadata tabulate --m-input-file stats-dada.qza --o-visualization stats-dada.qzv
  
  #STEP 6: IMPORT YOUR REFERENCE DATABASE. Create a database folder from your main directory (/home/fleasi) so it can be used for any of your project
  mkdr database
  cd database
  #We are using the manually curated SILVA database 
  #import the database into a .qza file recognized by qiime2. go into the "database" directory
  #The databases has to be downloaded onto the server from the the ARB-SILVA website: https://www.arb-silva.de/download/archive/qiime
  wget https://www.arb-silva.de/fileadmin/silva_databases/qiime/Silva_132_release.zip 
  # unzip the file 
  unzip -xvzf Silva_132_release.zip 
  #you are in your database folder, now extract the two files of interest ino a qza filet. First, the sequences.
  qiime tools import --type FeatureData[Sequence] --input-path SILVA_132_QIIME_release/rep_set/rep_set_16S_only/99/silva_132_99_16S.fna --output-path 99_otus_16S 
  #now extract the taxonomic information
  qiime tools import --type FeatureData[Taxonomy] --input-path SILVA_132_QIIME_release/taxonomy/16S_only/99/majority_taxonomy_7_levels.txt --source-format HeaderlessTSVTaxonomyFormat --output-path majority_taxonomy_7_levels#For eukaryotic 18S data the databases are pretty sparse, it is recommended using the majority_taxonomy_7_levels.txt since it does a better job of incorporating 
  #"environmental" rRNA sequences and the seven levels have been manually curated to better reflect the known phylogenetic classifications of diverse eukarytoic groups.
  
  #STEP 7. CLASSIFY SEQUENCES AND ASSIGN TAXONOMIC NAMES
  #it is essential to understand the value of pairwise identity. I use 90%, wich is the usual cutoff for phylum. So, all the sequences that are not 
  #at least 90% similar to what is in the database will result unassigned. Increasing the number would increase accuracy (--cutoff_species 97 --cutoff_family 93 --cutoff_phylum 90)
  #however, you would lose information because too many sequences will result unassigned. 
  #take a look at the code below and make sure it is clear.
  #rep-seqs-f15-210_r80-140.qza is your input sequences after trimming
  #silva_18S_reference_taxonomy.qza is the taxonomy you have extracted from Silva, as you noticed, I transfer that file into a directory here: /home/fleasi/databases/Qiime_18S_data/ so you will never have to change your script for future works
  #silva_18S_reference.qza is the file with the sequences extracted from Silva. Again, I transfer it into the same folder as above
  #The output file generated by the "--o-search-results" option contains the raw BLAST search results. These results include information about the best hits for each query sequence, including the reference sequence IDs, E-values, bit scores, and alignment lengths.
  #The output file generated by the "--o-classification" option contains the taxonomic classifications assigned to each query sequence based on the BLAST search results. This output file includes a table that shows the taxonomic lineage for each query sequence, as well as the confidence scores for each taxonomic assignment.
  nohup qiime feature-classifier classify-consensus-blast --i-query sequences_filtered.qza --i-reference-taxonomy majority_taxonomy_7_levels_16s.qza --i-reference-reads 99_otus_16S.qza  --o-search-results blast-search-results-97.qza --o-classification classification-97.qza --p-perc-identity 0.97 --p-maxaccepts 1 &  
    #STEP 8. View the output files using qiime2 view
    qiime metadata tabulate --m-input-file classification-final.qza --o-visualization classification-final.qzv 
  qiime metadata tabulate --m-input-file blast-search-results-97.qza --o-visualization blast-search-results-97.qzv 
  
  #STEP 9. What to do with this classification? You can download a TSV file and open it with excel, then play around. What taxa make sense and what taxa you should take off? That depends also on your research question.
  #Once you have figured out, it is time to filter your dataset and retain only what you want
  #what I do is not the most elegant way, I know there is one easier and more straightforward but I need some time to look for it, so, in a rushed situation here it goes.
  #let's filter your output sv-table.qza The table has the list of features (=OTUs) organized by sample. You need to replace names beased on your output
  qiime taxa filter-table --i-table sv-table_f100_247.qza --i-taxonomy classification-f100-247.qza --p-exclude Unassigned --o-filtered-table sv-table-no-unass.qza 
  #I just put unassigned for the moment because it's worth spending a few hours looking at the taxonomy and figure out what to discard. More taxa can be added by typing --p-exclude Unassigned, taxon1, taxon2, ...
  #next do the same with your sequences
  qiime taxa filter-seqs --i-sequences rep-seqs_f100_247.qza --i-taxonomy classification-97.qza --p-exclude Chloroplast --o-filtered-sequences sequences-no-chloro.qza
  #next filter the classification, so this is the very unelegant way...such as what I do is re-running step7 with new filtered files. I know there is a way to filter the classification. I just prefer to tell you what I know right away so we are not stalling
  
  
  #extract table
  qiime tools export --input-path sv-table_f100_247.qza --output-path exported-feature-table-nofilter
  #convert .biom into tsv
  biom convert -i feature-table.biom -o feature-table.tsv --to-tsv
  # Filter 
  filter_taxa_from_otu_table.py -i feature-table.biom -o filtered_feature_table.biom -n "Chloroplast"
  
  # Step 10 Filter
  # For 16s, I filtered out unassigned, chloroplast, and any SVs present in less than 1 sample with less than 10 reads
  #filter features based on their ID. This is easy but first you need to create an excel file including only the feature IDs (eg, 507de02aec1f834850a8ca01adfc8d73) you want to keep. 
  #You have the complete list in column 1 named "OTU". In column 2, you copy and paste what Fernando gave you
  #column 2 is named "todelete" You can do it in R
  otus<-read.csv('OTUs.csv', header=T)
  names_to_delete <- otus$todelete
  filtered <- otus[!otus$OTU %in% names_to_delete, ]
  write.csv(filtered,"/Users/qkr945/Desktop/will/filtered.csv")
  
  #Now, you have the list of otus you want to keep in column 1 of your csv. Delete all the extra information and name column 1 like that: '#OTU ID' without quotations
  #convert it into a txt and then tsv file and import in qiime
  #Then run this script. I am not sure if the final table was f15-210_r80-140. We may go back and see which one is the final and delete the other ones. 
  qiime feature-table filter-features --i-table sv-table-f15-210_r80-140.qza --m-metadata-file filtered.tsv --o-filtered-table sv-table-filtered.qza
  
  #once you have filtered the feature table, you want to use it as a reference to filter your sequences from your original sequence file
  qiime feature-table filter-seqs --i-data rep-seqs-f15-210_r80-140.qza --i-table sv-table-complete-filtered.qza --o-filtered-data rep-seqs-complete-filtered.qza
  
  #I now import the metadata file after saving it in .tsv
  scp -r  Desktop/will/mapping-file-18s.tsv fleasi@ts.simcenter.utc.edu:/home/fleasi/will_fernando/
    
    #finally, we can get the barplot, but first (there is probably a better way), I reclassify the filtered data through SILVA using a 90% cutoff
    nohup qiime feature-classifier classify-consensus-blast --i-query rep-seqs-complete-filtered.qza --i-reference-taxonomy ~/databases/Qiime_18S_data/silva_18S_reference_taxonomy.qza --i-reference-reads ~/databases/Qiime_18S_data/silva_18S_reference.qza  --o-classification classification-filtered.qza --p-perc-identity 0.90 --p-maxaccepts 1 &
    
    #barplot
    qiime taxa barplot --i-table sv-table-f100_247.qza --i-taxonomy classification-97-filtered.qza --m-metadata-file 16s_metadata.tsv  --o-visualization taxa-bar-plots-16s.qzv
  
  
  #to filter ASVs (=amplicon sequence variants, used sometimes as a synonym of OTU, but they are different) by number of the number of reads (10 reads minimum per ASV)
  qiime feature-table filter-samples --i-table sv-table-filtered.qza --p-min-frequency 10 --o-filtered-table sv-table-filtered-10reads.qza
  
  #to filter ASVs by number of the samples they are represented (discard the ones present in only one sample)
  qiime feature-table filter-features --i-table sv-table-filtered-10reads.qza --p-min-samples 3 --o-filtered-table sv-table-filtered-10reads-1sample.qza
  
  #now, use the last table to get your list of sequences and redo the classification in case you lost some SV (pretty sure there is away to filter from the classification without redoing the blast...I will check one day..)
  qiime feature-table filter-seqs --i-data sequences-filtered.qza --i-table sv-table-filtered-10reads-1sample.qza --o-filtered-data rep-seqs-filtered-10reads-1sample.qza
  #Classification
  nohup qiime feature-classifier classify-consensus-blast --i-query rep-seqs-filtered-10reads-1sample.qza --i-reference-taxonomy majority_taxonomy_7_levels_16s.qza --i-reference-reads 99_otus_16S.qza  --o-search-results blast-search-results-final.qza --o-classification classification-final.qza --p-perc-identity 0.97 --p-maxaccepts 1 &  
    
    #to pool SVs by species + site, first add the new column in the tsv file to create such category per each single sample. Let's say, you call the column 'speciesite'
    #Therefore, make the new table with samples pooled in that category. Use it just for the barplot, the rest of the analyses very likely will need each single sample separated. 
    qiime feature-table group --i-table sv-table-filtered-10reads-1sample.qza --p-axis 'sample' --m-metadata-file 16s_metadata.tsv --m-metadata-column "Site_x_species" --p-mode 'mean-ceiling' --o-grouped-table table_grouped_by-speciesite.qza
  #you don't have to produce new sequences or new classification for this grouping
  
  #to extract fasta file
  qiime tools export --input-path rep-seqs-filtered-10reads-1sample.qza --output-path 16s-fasta-sequences-filtered
  
#### PERMANOVA ###########
  
  # Import data (files are in Cloud/project)
  # The otus2 file is the matrix of samples (rows) and microbial ASVs (cols). It must have the exact same rows as the metadata file (env)
  otus2<-read.csv("t_16s_matrix_nowater.csv", header = TRUE, row.names = 1)
  env<-read.csv("16s_metadata_nowater.csv", header = TRUE)
  # I sometimes attach env just so that I don't have to path to it everytime, but this can get messy later on if you have multiple env files loaded
  attach(env)
  
  # Adonis
  library(vegan)
  # To randomize put NULL, if we want reproducible results can set seed to any number
  set.seed(NULL)
  # Jaccard: This model only acknowledged presence/absence, this was primarily what we used due to the imperfectness of read counts
  ## You can use Strata to limit the boundaries of the analysis, for example the second test only takes into account species that were found on the same date (date is largely equal to sampling session)
  ## You can also use * to get the interaction of the variables. The interaction was pretty much never significant for us, meaning Site and Species affect 16S CC independantly
  effectsjaccard <- vegan::adonis2(otus2~Site, permutations=999, methods="jaccard", binary=TRUE)
  effectsjaccard
  effectsjaccard <- vegan::adonis2(otus2~Species, Strata = Date, permutations=999, methods="jaccard", binary=TRUE)
  effectsjaccard
  # Bray-curtis: This model takes abundance data into account. We used this too but the results were pretty much the same as jaccard, jaccard is what the manuscript results are from
  effectsbray <- vegan::adonis2(otus2~Species*Site, permutations=999, methods="bray", binary=FALSE)
  effectsbray
  effectsbray <- vegan::adonis2(otus2~Date, permutations=999, methods="bray", binary=FALSE)
  effectsbray
  
  ## Subsetting - I used this basically to test if more phylogenetically distant taxa have more different microbiomes. For example, if the explanatory variable is Callistia, that means it compared if callistia is significantly distinct form everything else. There's a way to do this in R but it seemed easier for me to just make these new columns in excel
  Callistia <- vegan::adonis2(otus2~env$Callistia, Strata = Date, permutations=999, methods="jaccard", binary=TRUE)
  Callistia
  Venusta <- vegan::adonis2(otus2~env$Venusta, Strata = Date, permutations=999, methods="jaccard", binary=TRUE)
  Venusta
  Trichroistia <- vegan::adonis2(otus2~env$Trichroistia, Strata = Date, permutations=999, methods="jaccard", binary=TRUE)
  Trichroistia
  Lutrensis <- vegan::adonis2(otus2~env$Lutrensis, Strata = Date, permutations=999, methods="jaccard", binary=TRUE)
  Lutrensis
  
  ## Remove columns from dataframe
  # this is to remove all ASVs associated with diet
  remove_columns <- function(df, columns) {
    df[, !(names(df) %in% columns)]
  }
  
  diet<-read.csv('diet_correlated_16S_ASVs.csv', header=T)
  columns_to_remove <- diet$column1
  
  
  no_diet <- remove_columns(otus2, columns_to_remove)
  effectsjaccard <- vegan::adonis2(no_diet~Site, permutations=999, methods="jaccard", binary=TRUE)
  effectsjaccard
  effectsjaccard <- vegan::adonis2(no_diet~Species, permutations=999, methods="jaccard", binary=TRUE)
  effectsjaccard
  effectsjaccard <- vegan::adonis2(no_diet~Date, permutations=999, methods="jaccard", binary=TRUE)
  effectsjaccard
  
##### NMDS  ######
  # I made a bunch of NMDS plots, and for each one I needed a different ASV matrix and metadata file. You can subset data in R but I tried to learn and it seemed like to much work :/
  # I didn't end up needing all these packages but it can't hurt to install them all right??
  library(tidyverse)
  library(readxl)
  library(ggtext)
  library(ggplot2)
  library(ggalt)
  library(ggsci)
  library(vegan)
  
  ## Big plot with everything (except water)
  otus2<-read.csv('t_16s_matrix_nowater.csv', header=T, row.names = 1)
  env<-read.csv("16s_metadata_nowater.csv", header = TRUE)
  
  nmds<-metaMDS(otus2, distance= "jaccard")
  
  site.scrs <- as.data.frame(vegan::scores(nmds, display = "sites"))
  site.scrs <- cbind(site.scrs, Location = env$Site)
  site.scrs <- cbind(site.scrs, Species = env$Species)
  
  ### Sites colored
  nmds.plot <- ggplot(site.scrs, aes(x = NMDS1, y = NMDS2)) + 
    geom_point(aes(color = env$Site_number, shape = env$Species), 
               size = 2) +
    coord_fixed() +
    theme_classic() + 
    scale_shape_manual(values= c(21,22,23,24,25)) +
    theme(panel.background = element_rect(fill = NA, colour = "black", size = 2, linetype = "solid")) +
    labs(fill = "Location", shape = "Species", color = "Location") + 
    theme(legend.position = "right", legend.text = element_text(size = 10), 
          legend.title = element_text(size = 10), axis.text = element_text(size = 10),
          legend.key.size = unit(1, "lines")) +
    expand_limits(x = c(-5, 5), y = c(-5, 5)) 
  
  nmds.plot
  
  ### Species colored
  
  nmds.plot <- ggplot(site.scrs, aes(x = NMDS1, y = NMDS2)) + 
    geom_point(aes(fill = env$Species, color = env$Species), 
               size = 3, stroke = 0) +
    coord_fixed() +
    theme_classic() + 
    theme(panel.background = element_rect(fill = NA, colour = "black", size = 2, linetype = "solid")) +
    labs(fill = "Location", shape = "Species", color = "Location") + 
    theme(legend.position = "right", legend.text = element_text(size = 10), 
          legend.title = element_text(size = 10), axis.text = element_text(size = 10),
          legend.key.size = unit(1, "lines")) +
    expand_limits(x = c(-5, 5), y = c(-5, 5)) 
  
  nmds.plot
  
  ## Weiss only
  otus2w<-read.csv('t_16s_matrix_weiss.csv', header=T)
  envw<-read.csv("16s_metadata_weiss.csv", header = TRUE)
  
  nmdsw<-metaMDS(otus2w, distance= "jaccard")
  
  site.scrsw <- as.data.frame(vegan::scores(nmdsw, display = "sites"))
  site.scrsw <- cbind(site.scrsw, Location = envw$Site)
  site.scrsw <- cbind(site.scrsw, Species = envw$Species)
  
  nmds.plotw <- ggplot(site.scrsw, aes(x = NMDS1, y = NMDS2)) + 
    geom_point(aes(color = envw$Sampling_session, shape = envw$Species), 
               size = 3) +
    coord_fixed() +
    theme_classic() +
    scale_shape_manual(values= c(21,22,23)) +
    theme(panel.background = element_rect(fill = NA, colour = "black", size = 2, linetype = "solid")) +
    labs(fill = "Species", shape = "Species", color = "Sampling Session") + 
    theme(legend.position = "right", legend.text = element_text(size = 10), 
          legend.title = element_text(size = 10), axis.text = element_text(size = 10),
          legend.key.size = unit(1, "lines")) +
    expand_limits(x = c(-5, 5), y = c(-5, 5)) 
  
  nmds.plotw
  
  ## No turkey (no native lutrensis)
  otus2t<-read.csv('t_16s_matrix_noKansas.csv', header=T)
  envt<-read.csv("16s_metadata_nokansas.csv", header = TRUE)
  
  nmdst<-metaMDS(otus2t, distance= "jaccard")
  
  site.scrst <- as.data.frame(vegan::scores(nmdst, display = "sites"))
  site.scrst <- cbind(site.scrst, Location = envt$Site)
  site.scrst <- cbind(site.scrst, Species = envt$Species)
  
  nmds.plott <- ggplot(site.scrst, aes(x = NMDS1, y = NMDS2)) + 
    geom_point(aes(color = envt$Site_number, shape =envt$Invasive), 
               size = 3) +
    coord_fixed() +
    theme_classic() + 
    scale_shape_manual(values= c(21,22)) +
    theme(panel.background = element_rect(fill = NA, colour = "black", size = 2, linetype = "solid")) +
    labs(fill = "Location", shape = "Species", color = "Location") + 
    theme(legend.position = "right", legend.text = element_text(size = 10), 
          legend.title = element_text(size = 10), axis.text = element_text(size = 10),
          legend.key.size = unit(1, "lines")) +
    expand_limits(x = c(-5, 5), y = c(-5, 5)) 
  
  nmds.plott
  
  ## lutrensis only
  otus2l<-read.csv('t_16s_matrix_lutrensisonly.csv', header=T)
  envl<-read.csv("16s_metadata_lutrensisonly.csv", header = TRUE)
  
  nmdsl<-metaMDS(otus2l, distance= "jaccard")
  
  site.scrsl <- as.data.frame(vegan::scores(nmdsl, display = "sites"))
  site.scrsl <- cbind(site.scrsl, Location = envl$Watershed)
  site.scrsl <- cbind(site.scrsl, Species = envl$Species)
  
  nmds.plotl <- ggplot(site.scrsl, aes(x = NMDS1, y = NMDS2)) + 
    geom_point(aes(color = envl$Watershed, shape = envl$Site_number), 
               size = 3) +
    coord_fixed() +
    theme_classic() + 
    expand_limits(x = c(-5, 5), y = c(-5, 5)) +
    scale_shape_manual(values= c(21,22,23,24,25)) +
    theme(panel.background = element_rect(fill = NA, colour = "black", size = 2, linetype = "solid")) +
    labs(fill = "Watershed", shape = "Site", color = "Watershed") + 
    theme(legend.position = "right", legend.text = element_text(size = 10), 
          legend.title = element_text(size = 10), axis.text = element_text(size = 10),
          legend.key.size = unit(1, "lines")) +
    ggtitle("C. lutrensis only")
  
  nmds.plotl
  
  ## If you're relying only on R for plots this patchwork tool is nice for putting all together. But I exported them seperately and used illustrator
  library(patchwork)
  (nmds.plot|nmds.plott)/(nmds.plotl|nmds.plotw)
  
#### Mantel tests #####
  library(ape)
  library(ade4)
  # I did three of these, one comparing the 16S fish sample matrix with geographic distance matrix, one comparing the 16S water sample matrix with geo distance, and one comparing 16S with 18S matrix
  
  ## For Water
  # Create distance matrix for community composition
  w_community<- read_csv("t_16s_matrix_water.csv")
  w_community
  microbe.dist <- vegdist(w_community)
  # Create distance matrix for geographic distance
  w_metadata <- read_csv("16s_water_metadata.csv")
  w_metadata
  geo.dists <- dist(cbind(w_metadata$Longitude, w_metadata$Latitude))
  # Mantel test
  mantel.rtest(microbe.dist, geo.dists, nrepet = 9999)
  # Non significant p-value indicates that the community composition of the water sample is NOT correlated with geographic distance. Likely other factors, such as type and quality of water body have more meaning
  
  ## For fish
  # Create distance matrix for geographic distance
  geo.dist <- dist(cbind(env$Longitude, env$Latitude))
  # Create distance matrix for community composition
  microbe.dist <- vegdist(otus2)
  mantel.rtest(microbe.dist, geo.dist, nrepet = 999)
  # No correlation between geographic distance and fish microbiome community composition
  
  ## For diet
  otus18 <- read.csv('18s_matrix_compatible.csv', header=T, row.names = 1)
  otus16 <- read.csv('16s_matrix_compatible.csv', header=T, row.names = 1)
  
  dist18 <- vegdist(otus18)
  dist16 <- vegdist(otus16)
  
  mantel.rtest(dist16, dist18, nrepet = 9999)

  
  
##### Boxplots #####
  # These were used to display alpha diversity (PD and richness) information
  OTUSpeciesboxplot <- ggplot(env, aes(x=Species_number, y=OTU_count, color = Species)) + geom_boxplot() +
    ggtitle("Number of microbiota ASVs per Species") +
    xlab("Species") + ylab("# ASVs") +
    theme_classic()
  OTUSpeciesboxplot
  
  OTUSiteboxplot <- ggplot(env, aes(x=Site_number, y=OTU_count, color = Watershed)) + geom_boxplot() +
    ggtitle("Number of microbiota ASVs per Site") +
    xlab("Site") + ylab("# ASVs") +
    theme_classic()
  OTUSiteboxplot
  
  PDSpeciesboxplot <- ggplot(env, aes(x=Species_number, y=X16s_PD, color = Site)) + geom_boxplot() +
    ggtitle("Phylogenetic Diversity per Species") +
    xlab("Species") + ylab("Phylogenetic Diversity") +
    theme(legend.position="none") +
    theme_classic()
  
  PDSpeciesboxplot
  
  PDSiteboxplot <- ggplot(env, aes(x=Site_number, y=X16s_PD, color = Watershed)) + geom_boxplot() +
    ggtitle("Phylogenetic Diversity per Site") +
    xlab("Site") + ylab("Phylogenetic Diversity") +
    theme_classic()
  PDSiteboxplot
  
  
  # Invasive watershed PD/ OTU figures
  env<-read.csv("16s_metadata_lutrensisonly.csv", header = TRUE)
  
  t.test(env$X16s_PD ~ env$Lutrensis)
  
  PDSiteboxplot <- ggplot(env, aes(x=Watershed, y=X16s_PD, color = Lutrensis)) + geom_boxplot() +
    ggtitle("Phylogenetic Diversity per Watershed") +
    xlab("Watershed") + ylab("Phylogenetic Diversity") +
    theme_classic()
  PDSiteboxplot
  
  OTUSiteboxplot <- ggplot(env, aes(x=Watershed, y=OTU_count, color = Lutrensis)) + geom_boxplot() +
    ggtitle("Number of microbiota ASVs per Watershed") +
    xlab("Watershed") + ylab("# ASVs") +
    theme_classic()
  OTUSiteboxplot
  
  library(patchwork)
  (PDSpeciesboxplot|PDSiteboxplot)/(OTUSpeciesboxplot|OTUSiteboxplot)
  (PDSpeciesboxplot/OTUSpeciesboxplot)
  (PDSiteboxplot/OTUSiteboxplot)
  ## Weiss lake only
  env<-read.csv("16s_metadata_weiss.csv", header = TRUE)
  t.test(env$X16s_PD ~ env$Lutrensis)
  
  PDSiteboxplot <- ggplot(env, aes(x=Species, y=X16s_PD, color = Lutrensis)) + geom_boxplot() +
    ggtitle("Phylogenetic Diversity per Watershed") +
    xlab("Watershed") + ylab("Phylogenetic Diversity") +
    theme_classic()
  PDSiteboxplot
  
  ## Sex
  env<-read.csv("16s_metadata_sex.csv", header = TRUE)
  t.test(env$X16s_PD ~ env$Sex)
  
  PDSiteboxplot <- ggplot(env, aes(x=Sex, y=X16s_PD)) + geom_boxplot() +
    ggtitle("Phylogenetic Diversity per Watershed") +
    xlab("Watershed") + ylab("Phylogenetic Diversity") +
    theme_classic()
  PDSiteboxplot

##### Linear models ####
  
  library(lme4)
  env<-read.csv("16s_metadata_nowater.csv", header = TRUE)
  attach(env)
  lmerSite <- lmer(X16s_PD~Reads_count +(1|OTU_count))
  lmsum <- summary(lmerSite)
  lmsum
  anova(lmerSite)
  
  model1 <- lmer(OTU_count~Sex +(1|Reads_count))
  model2 <- lmer(OTU_count~TBL +(1|Reads_count))
  model3 <- lmer(OTU_count~Species +(1|Reads_count))
  model4 <- lmer(OTU_count~Site +(1|Reads_count))
  model5 <- lmer(OTU_count~Date )
  models <- list(model1, model2, model3, model4, model5)
  aictab(cand.set = models)
  
  lmerSite
  lmerpredictions <- data.frame(predict(lmerSite))
  lmerpredictions$distance_observed <- lmerSite$X16s_PD
  
  install.packages("AICcmodavg")
  library(AICcmodavg)
  model1 <- lm(OTU_count~Sex)
  model1 <- lm(OTU_count~Reads_count)
  
  model2 <- lm(OTU_count~TBL)
  model3 <- lm(OTU_count~Species)
  model4 <- lm(OTU_count~Site)
  model5 <- lm(OTU_count~Date)
  models <- list(model1, model2, model3, model4, model5)
  aictab(cand.set = models)
  
  model1 <- lm(X16s_PD~Sex)
  model2 <- lm(X16s_PD~TBL)
  model1 <- lm(X16s_PD~Species)
  model2 <- lm(X16s_PD~Site)
  model3 <- lm(X16s_PD~Date)
  models <- list(model1, model2, model3)
  aictab(cand.set = models)
  
  model1 <- lm(OTU_count~Species)
  model2 <- lm(OTU_count~Site)
  model3 <- lm(OTU_count~Date)
  model4 <- lm(OTU_count~Species * Site)
  model5 <- lm(OTU_count~Site * Date)
  model6 <- lm(OTU_count~Date * Species)
  model7 <- lm(OTU_count~Date * Species * Site)
  models <- list(model1, model2, model3, model4, model5, model6, model7)
  aictab(cand.set = models)
  
  
  
##### Network #####
  ## I made the network in cytoscape, this is how I prepared the input files
  # First, this isn't necessarily part of making a network, but I had to do this to turn the 18S clades into a presence/absence matrix
  # Dataframe to matrix
  vec <- read.csv('18s_subphylum_vectors.csv', header=T)
  mat <- table(vec$SampleID, vec$Subphylum1)
  mat2 <- as.matrix(mat)
  # If it's the wrong way, transpose it
  mat2 <- t(mat2)
  # Now you need to make a correlation table - you could use the cor function for this, but I prefer rcorr because it gives you a p value
  library(Hmisc)
  rcorr18 <- rcorr(as.matrix(mat2), type = c("spearman"))
  # Cytoscape needs a table not a matrix, so you have to flatten the correlation matrix with the below function
  
  flattenCorrMatrix <- function(cormat, pmat) {
    ut <- upper.tri(cormat)
    data.frame(
      row = rownames(cormat)[row(cormat)[ut]],
      column = rownames(cormat)[col(cormat)[ut]],
      cor  =(cormat)[ut],
      p = pmat[ut]
    )
  }
  cor.table18 <- flattenCorrMatrix(rcorr18$r, rcorr18$P)
  # remove p value > 0.05
  cor.table.p18 <- cor.table18[cor.table18$p <= 0.05, ]
  # remove cor < 0.5
  cor.table.pc18 <- cor.table.p18[cor.table.p18$cor >= 0.5, ]
  write.csv(cor.table.p18, file = "cor_table_18p", row.names = TRUE)
  ## This csv will probably be huge, but you can trim it down more in excel (I cut out all correlations between two 16S ASVs. 
  ## You will also want a metadata table for cytoscape - luckily, it doesn't need equal rows as the cor table, so this is pretty easy
  
###### Map #####
  # I made a couple of these, the first using open street map data and ggplot2 and the second more simple with the maps package
  library(ggplot2)
  library(tidyverse)
  library(maps)
  library(ggmap)
  library(ggthemes)
  Sitedata <- read.csv("Site_Metadata.csv")
  
  ## ggplot2 map
  basemap <- get_stamenmap(
    bbox = c(left = -88, bottom = 32.5, right = -82, top = 35.5), 
    maptype = "terrain",
    zoom = 8
  )
  
  smallmap <- ggmap(basemap) +
    geom_point(data = Sitedata,
               aes(x = Longitude, y = Latitude, color = Site, shape = Watershed),
               size = 3) + 
    theme_map() +
    theme(legend.background = element_blank()) + 
    scale_color_manual(values = c("chocolate4","maroon","magenta2","purple", "navyblue", "turquoise3","springgreen3","gold","tomato"))
  
  
  map2 <- get_stamenmap(
    bbox = c(left = -98, bottom = 32.5, right = -82, top = 42), 
    maptype = "terrain",
    zoom = 5
  )
  
  bigmap <- ggmap(map2) +
    geom_point(data = Sitedata,
               aes(x = Longitude, y = Latitude, color = Site, shape = Watershed),
               size = 2) + 
    theme_map() + 
    theme(legend.background = element_blank()) + 
    scale_color_manual(values = c("chocolate4","maroon","magenta2","purple", "navyblue", "turquoise3","springgreen3","gold","tomato"))+
    theme(legend.position = "none")  
  
  bigmap
  
  
  ## Combine
  
  library(cowplot)
  
  ggdraw() +
    draw_plot(smallmap) + 
    draw_plot(bigmap, x = 0.475, y = 0.55, width = 0.4, height = 0.4) + 
    theme(legend.background = element_blank()) + 
    scale_color_manual(values = c("chocolate4","maroon","magenta2","purple", "navyblue", "turquoise3","springgreen3","yellow2","tomato"))
  
  ### Map
  install.packages("mapdata")
  install.packages("maptools")
  library(maps)
  library(mapdata)
  library(maptools) #for shapefiles
  library(sp)
  library(sf)
  library(scales) #for transparency
  
  ## The rivers is a shp file from Alda
  rivers_l<-st_read("hydrography_l_rivers_v2_Proj/hydrography_l_rivers_v2_Proj.shp")
  
  map("usa", xlim=c(-87,-84), ylim=c(33,35.5))
  map("state", add=TRUE, lwd=1)
  plot(rivers_l, add=TRUE, xlim=c(-87,-84), ylim=c(33,35.5), col="grey", lwd=1, border=FALSE)
  points(Sitedata$Longitude, Sitedata$Latitude, pch=19, col= c("navyblue","tomato","orange","purple", "magenta", "olivedrab","springgreen3","powderblue","dodgerblue"), cex=2)
  
  map("usa", xlim=c(-98,-82), ylim=c(31,42))
  map("state", add=TRUE, lwd=1)
  plot(rivers_l, add=TRUE, xlim=c(-98,-82), ylim=c(31,42), col="grey", lwd=1, border=FALSE)
  points(Sitedata$Longitude, Sitedata$Latitude, pch=19, col= c("navyblue","tomato","orange","purple", "magenta", "olivedrab","springgreen3","powderblue","dodgerblue"), cex=1)
  
  # I just made the legend and combined them in illustrator
  
#### Phylosymbiosis ####
 ## Genetic distance (cyt b ) vs community composition distance
  install.packages("ape")
  library(ape)
  library(ade4)
  library(vegan)
  seq <- read.dna("cytbseq_same.fasta", format = "fasta")
  seqdist <- dist.dna(seq, model = "TN93")
  
  otus16 <- read.csv('16s_matrix_cytb_compatible.csv', header=T, row.names = 1)
  dist16 <- vegdist(otus16, method = "bray")
  
  mantel.rtest(dist16, seqdist, nrepet = 9999)
  
  ## P value greater than .05 indicates correlation of genetic distance and community composition is non significant 
  