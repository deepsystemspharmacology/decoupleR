#' decouple
#'
#' Calculate the TF activity per sample out of a gene expression matrix by
#' coupling a regulon network with a variety of statistics.
#'
#' @inheritParams .decoupler_mat_format
#' @inheritParams .decoupler_network_format
#' @param statistics Statistical methods to be coupled.
#' @param args A list of argument-lists the same length as `statistics`
#'  (or length 1). The default argument, list(NULL), will be recycled to the
#'  same length as `statistics`, and will call each function with no arguments
#'   (apart from `mat`, `network`, `.source` and, `.target`).
#' @param show_toy_call The call of each statistic must be informed?
#'
#' @return A long format tibble of the enrichment scores for each tf
#'  across the samples. Resulting tibble contains the following columns:
#'  1. `statistic`: Indicates which method is associated with which score.
#'  2. `tf`: Source nodes of `network`.
#'  3. `condition`: Condition representing each column of `mat`.
#'  4. `score`: Regulatory activity (enrichment score).
#'  5. `statistic_time`: Internal execution time indicator.
#'  6. `...`: Columns of metadata generated by certain statistics.
#' @export
#' @import purrr
#' @family decoupleR statistics
#' @examples
#' inputs_dir <- system.file("testdata", "inputs", package = "decoupleR")
#'
#' mat <- readRDS(file.path(inputs_dir, "input-expr_matrix.rds"))
#' network <- readRDS(file.path(inputs_dir, "input-dorothea_genesets.rds"))
#'
#' decouple(
#'     mat = mat,
#'     network = network,
#'     .source = "tf",
#'     .target = "target",
#'     statistics = c("gsva", "mean", "pscira", "scira", "viper"),
#'     args = list(
#'         gsva = list(verbose = FALSE),
#'         mean = list(.mor = "mor", .likelihood = "likelihood"),
#'         pscira = list(.mor = "mor"),
#'         scira = list(.mor = "mor"),
#'         viper = list(
#'             .mor = "mor",
#'             .likelihood = "likelihood",
#'             verbose = FALSE
#'        )
#'     )
#' )
decouple <- function(
    mat,
    network,
    .source,
    .target,
    statistics,
    args = list(NULL),
    show_toy_call = FALSE) {

    # Match statistics to couple ----------------------------------------------
    statistics <- .select_statistics(statistics)

    # Evaluate statistics -----------------------------------------------------

    mat_symbol <- .label_expr({{ mat }})
    network_symbol <- .label_expr({{ network }})

    # For the moment this will only ensure that the parameters passed
    # to decoupleR are the same when invoking the functions.
    map2_dfr(
        .x = statistics,
        .y = args,
        .f = .invoke_statistic,
        mat = mat,
        network = network,
        .source = {{ .source }},
        .target = {{ .target }},
        mat_symbol = {{ mat_symbol }},
        network_symbol = {{ network_symbol }},
        show_toy_call = show_toy_call,
        .id = "run_id"
    ) %>%
        select(
            .data$run_id,
            .data$statistic,
            .data$tf,
            .data$condition,
            .data$score,
            .data$statistic_time,
            everything()
        )
}

# Helpers -----------------------------------------------------------------
#' Choose statistics to run
#'
#' It allows the user to select multiple statistics to run,
#' no matter if they are repeated or not.
#'
#' @details
#' From the user perspective, this could be useful since any traceback
#' would look something like decoupleR::run_{statistic}().
#'
#' @inheritParams decouple
#'
#' @return list of expressions of statistics to run.
#' @keywords internal
#' @noRd
.select_statistics <- function(statistics) {
    available_statistics <- list(
        mean = expr(run_mean),
        scira = expr(run_scira),
        pscira = expr(run_pscira),
        viper = expr(run_viper),
        gsva = expr(run_gsva)
    )

    statistics %>%
        match.arg(names(available_statistics), several.ok = TRUE) %>%
        available_statistics[.] %>%
        unname()
}

#' Construct an expression to evaluate a decoupleR statistic.
#'
#' @details
#' `.invoke_statistic()` was designed because [purrr::invoke_map_dfr()] is retired.
#' The alternative proposed by the developers by purrr is to use [rlang::exec()] in
#' combination with [purrr::map2()], however, the function is not a quoting function,
#' so the parameters that require the `curly-curly` (`{{}}`) operator require a
#' special pre-processing. In practical terms, creating an expression of zero allows
#' us to have better control over the function call as suggested in the [rlang::exec()]
#' documentation. For instance, we can see how the function itself is being called.
#' Therefore, if an error occurs in one of the statistics, we will have a direct
#' traceback to the problematic call, as opposed to what happens directly using [rlang::exec()].
#'
#' @inheritParams decouple
#' @param fn Expression containing the name of the function to execute.
#' @param args Extra arguments to pass to the statistician under evaluation.
#'
#' @keywords internal
#' @noRd
.invoke_statistic <- function(fn,
    args,
    mat,
    network,
    .source,
    .target,
    mat_symbol,
    network_symbol,
    show_toy_call) {
    .toy_call <- expr(
        (!!fn)(
            mat = {{ mat_symbol }},
            network = {{ network_symbol }},
            .source = {{ .source }},
            .target = {{ .target }},
            !!!args)
    )

    if (show_toy_call) {
        utils::capture.output(rlang::qq_show(!!.toy_call)) %>%
            stringr::str_replace_all(pattern = "= \\^", "= ") %>%
            message()
    }

    .call <- expr(
        (!!fn)(
            mat = mat,
            network = network,
            .source = {{ .source }},
            .target = {{ .target }},
            !!!args)
    )

    eval(.call)
}

#' Convert object to symbol expression
#'
#' @param x An object or expression to convert to symbol
#'
#' @keywords internal
#' @noRd
.label_expr <- function(x) rlang::get_expr(enquo(x))
