#' Method for running KeyPathwayMineR localy
#'
#' @param indicator_matrices List of paths to the indicator matrices that will be used.
#' @param graph_file String. Path to graph_file.
#'
#' @return Saves the results in folder results.
call_kpm_local <- function(indicator_matrices, graph_file) {
  # Directory where input files and properties files are stored
  datasets_file <- system.file(package = "KeyPathwayMineR", "extdata/")
  properties_file <- paste(datasets_file, kpm_options()$properties_file, sep = "/")

  # Convert option parameters to java command line arguments
  args <- to_java_arguments(indicator_matrices = indicator_matrices, graph_file = graph_file)

  #### Initialize java objects ####
  main <- rJava::.jnew(class = "de/mpg/mpiinf/ag1/kpm/main/Main")
  path_to_local_results <- rJava::.jcall(
    obj = main,
    returnSig = "Ljava/lang/String;",
    method = "runR",
    args,
    rJava::.jnew(class = "java/lang/String", datasets_file),
    rJava::.jnew(class = "java/lang/String", properties_file)
  )

  return(save_local_results(path_to_local_results))
}

#' Method which transform kpm_options() to java arguments.
#'
#' Takes kpm_options and adds arguments to a list
#' @return String [] args array with the arguments
to_java_arguments <- function(indicator_matrices, graph_file) {
  # List with arguments for local execution
  arguments <- c()
  # Get algorithm ####
  arguments <- c(arguments, paste("-algo=", toupper(kpm_options()$algorithm), sep = ""))
  # Get remove border exceptions node flag  ####
  if (kpm_options()$remove_bens) arguments <- c(arguments, paste("-removeBens=", kpm_options()$remove_bens, sep = ""))
  # Get case exceptions L ####
  arguments <- get_case_exceptions(indicator_matrices = indicator_matrices, arguments = arguments)
  # Get perturbation parameters ####
  if (kpm_options()$with_perturbation) {
    arguments <- c(arguments, paste("-perturbation=",
                                    kpm_options()$perturbation_start, ",",
                                    kpm_options()$perturbation_step, ",",
                                    kpm_options()$perturbation_max, ",",
                                    kpm_options()$graphs_per_step,
                                    sep = ""
    ))

    arguments <- c(arguments, paste("-perturbationTechnique=", kpm_options()$perturbation_technique, sep = ""))
  }
  # Get graph file path ####
  arguments <- c(arguments, paste("-graphFile=", graph_file, sep = ""))
  # Get indicator matrices  ####
  for (i in 1:length(indicator_matrices)) {
    arguments <- c(arguments, paste("-matrix", i, "=", indicator_matrices[i], sep = ""))
  }
  # Computed pathways ####
  arguments <- c(arguments, paste("-maxSolutions=", kpm_options()$computed_pathways, sep = ""))
  # Combine operator if we have more than two matrices
  if (length(indicator_matrices) > 1) arguments <- c(arguments, paste("-combineOp=", kpm_options()$link_type, sep = ""))
  # Add strategy glone to arguments ####
  if (kpm_options()$strategy == "GLONE") arguments <- c(arguments, "-strategy=GLONE")
  # Add strategy INES to arguments ####
  if (kpm_options()$strategy == "INES") {
    arguments <- c(arguments, "-strategy=INES")
    arguments <- c(arguments, paste("-K=", kpm_options()$k_min, sep = ""))
    # TODO Obosolete if clause delete after discussion with Markus
    # if (kpm_options()$use_range_k) {
    #   arguments <- c(arguments, "-batch")
    #   arguments <- c(arguments, paste("-K_batch=",
    #     kpm_options()$k_min, ",",
    #     kpm_options()$k_step, ",",
    #     kpm_options()$k_max,
    #     sep = ""
    #   ))
    # } else if (!kpm_options()$use_range_k) {
    #   arguments <- c(arguments, paste("-K=", kpm_options()$k_min, sep = ""))
    # }
  }

  # Add results folder to arguments ####
  arguments <- c(arguments, paste("-resultsDir=", getwd(), "/results", sep = ""))

  # Get positive and negative nodes ####
  if (!is.null(kpm_options()$positive_nodes)) {
    positve_nodes_file <- tempfile(fileext = ".txt")
    write.table(x = kpm_options()$positive_nodes, file = positve_nodes_file, quote = F, col.names = F, row.names = F)
    arguments <- c(arguments, paste("-positiveFile=", positve_nodes_file, sep = ""))
  }
  if (!is.null(kpm_options()$negative_nodes)) {
    negative_nodes_file <- tempfile(fileext = ".txt")
    write.table(x = kpm_options()$negative_nodes, file = negative_nodes_file, quote = F, col.names = F, row.names = F)
    arguments <- c(arguments, paste("-negativeFile=", negative_nodes_file, sep = ""))
  }
  # Return arguments ####
  return(.jarray(arguments))
}

#' Creates java arguments for case exceptions
get_case_exceptions <- function(indicator_matrices, arguments) {
  # TODO Obosolete if clause delete after discussion with Markus
  for (i in 1:length(indicator_matrices)) {
    arguments <- c(arguments, paste("-L", i, "=", kpm_options()$l_min[i], sep = ""))
  }
  # Check whether it is a batch run or not
  # if (kpm_options()$use_range_l) {
  #   arguments <- c(arguments, "-batch")
  #   # Batch run for l parameter
  #   for (i in 1:length(indicator_matrices)) {
  #     arguments <- c(arguments, paste("-L", i, "_batch=", kpm_options()$l_min[i], ",",
  #       kpm_options()$l_step[i], ",",
  #       kpm_options()$l_max[i],
  #       sep = ""
  #     ))
  #   }
  # } else if (!kpm_options()$use_range_l) {
  #   # Normal run for l parameter
  #   for (i in 1:length(indicator_matrices)) {
  #     arguments <- c(arguments, paste("-L", i, "=", kpm_options()$l_min[i], sep = ""))
  #   }
  # }

  return(arguments)
}

#'  Save results of the local run
#'
#'  Method to save the results provided
#'  from the lccal run.
#'
#' @param path_to_results The path to the results folder of the local run
#'
#' @return Result object
#' @importFrom magrittr %>%
#' @importFrom gtools mixedsort
#' @importFrom tibble tibble
save_local_results <- function(path_to_results) {
  # List to save all configurations and pathways
  configurations <- list()
  # If path to results is not empty pathways were extracted
  if (path_to_results != "") {
    message(path_to_results)
    # If no results for specific configuration exist
    no_results <- FALSE

    # Read pathway stats file
    pathway_stats <- vroom::vroom(paste(path_to_results, "/pathways_stats.txt", sep = ""), delim = "\t")

    # Get all Case exception identifiers for current run.
    # E.g. 2 Datasets --> 2 Identifiers c(L1,L2)
    case_exception_identifiers <- names(pathway_stats)[startsWith(names(pathway_stats), "L")]

    # Sort identifiers
    case_exception_identifiers <- paste("L", as.numeric(gsub("L", "", case_exception_identifiers)), sep = "")

    # temp variable to
    old_configuration <- ""
    # Parse results
    for (pathway in 1:nrow(pathway_stats)) {
      # Determine configuration
      # Node-exceptions
      configuration <- paste("K-", pathway_stats[pathway, "K"], sep = "")

      # Case-exceptions
      for (identifier in case_exception_identifiers) {
        configuration <- paste(configuration, "-", identifier, "-", pathway_stats[pathway, identifier], sep = "")
      }

      # When the ID = 1 it means we have a new configuration
      if (as.numeric(pathway_stats[pathway, "PATHWAY_ID"]) == 1) {
        if (configuration != old_configuration && old_configuration != "") {
          # When the configuration changes the union network for the previous configuration is determined
          configurations[[old_configuration]]@union_network <- create_union_network(configuration = configurations[[old_configuration]])
        }
        # Create new configuration
        configurations[[configuration]] <- new("Configuration", configuration = configuration, k = as.numeric(pathway_stats[pathway, "K"]), l_values = as.list(unlist(pathway_stats[pathway, case_exception_identifiers])), pathways = list())

        # If the number of nodes and interactions for the current configuration is 0
        if (pathway_stats[pathway, "# NODES"] == 0 & pathway_stats[pathway, "# EDGES"] == 0) {
          no_results <- TRUE
          # skip to next iteration and do not read tables for this specific configuration
          next
        }

        if (pathway_stats[pathway, "# NODES"] != 0) {
          # Read nodes file for specific configuration
          nodes <- vroom::vroom(paste(path_to_results, "/pathway-", configuration, "-nodes-KPM.txt", sep = ""), delim = "\t", col_names = c("pathway", "node"))
        } else {
          nodes <- tibble::tibble(pathway = character(), node = character())
        }

        if (pathway_stats[pathway, "# EDGES"] != 0) {
          # Read interactions file for specific configuration
          interactions <- vroom::vroom(file = paste(path_to_results, "/pathway-", configuration, "-interactions-KPM.txt", sep = ""), delim = "\t", col_select = c(1, 2, 4), col_names = c("pathway", "source", "interaction", "target"))
        } else {
          interactions <- tibble::tibble(pathway = character(), source = character(), interaction = character(), target = character())
        }
        no_results <- FALSE
        old_configuration <- configuration
      }
      if (!no_results) {
        # Determine number of pathway for specific configuration
        pathway_num <- length(configurations[[configuration]]@pathways) + 1
        pathway <- paste("Pathway-", pathway_num, sep = "")

        # For current pathway(pathway_stats[i, "PATHWAY_ID"] = id) determine edges, nodes, stats
        configurations[[configuration]]@pathways <- append(
          configurations[[configuration]]@pathways,
          setNames(list(new("Pathway",
                            edges = dplyr::filter(interactions, pathway == pathway_num) %>% dplyr::select(c(2, 3)),
                            nodes = dplyr::filter(nodes, pathway == pathway_num) %>% dplyr::select(2),
                            num_edges = as.integer(pathway_stats[pathway, "# EDGES"]),
                            num_nodes = as.integer(pathway_stats[pathway, "# NODES"]),
                            avg_exp = as.numeric(pathway_stats[pathway, "AVG. DIFF. EXP. CASES"])
          )), pathway)
        )
      }
    }
    old_configuration <- configuration
    # Add the last union network
    configurations[[old_configuration]]@union_network <- create_union_network(configuration = configurations[[old_configuration]])
  }
  # Sort extracted pathways by conifugration name
  configurations <- configurations[gtools::mixedsort(names(configurations), decreasing = FALSE)]

  return(new("Result", parameters = kpm_options(), configurations = configurations))
}
