#' WikiSpecies
#'
#' @export
#' @template args
#' @family Wikispecies functions
#' @return `wt_wikispecies` returns a list, with slots:
#' \itemize{
#'  \item langlinks - language page links
#'  \item externallinks - external links
#'  \item common_names - a data.frame with `name` and `language` columns
#'  \item classification - a data.frame with `rank` and `name` columns
#' }
#'
#' `wt_wikispecies_parse` returns a list
#'
#' `wt_wikispecies_search` returns a list with slots for `continue` and
#' `query`, where `query` holds the results, with `query$search` slot with
#' the search results
#' @references <https://www.mediawiki.org/wiki/API:Search> for help on search
#' @examples \dontrun{
#' # high level
#' wt_wikispecies(name = "Malus domestica")
#' wt_wikispecies(name = "Pinus contorta")
#' wt_wikispecies(name = "Ursus americanus")
#' wt_wikispecies(name = "Balaenoptera musculus")
#'
#' # low level
#' pg <- wt_wiki_page("https://species.wikimedia.org/wiki/Abelmoschus")
#' wt_wikispecies_parse(pg)
#'
#' # search wikispecies
#' # FIXME: utf=FALSE for now until curl::curl_escape fix 
#' # https://github.com/jeroen/curl/issues/228
#' wt_wikispecies_search(query = "pine tree", utf8=FALSE)
#'
#' ## use search results to dig into pages
#' res <- wt_wikispecies_search(query = "pine tree", utf8=FALSE)
#' lapply(res$query$search$title[1:3], wt_wikispecies)
#' }
wt_wikispecies <- function(name, utf8 = TRUE, ...) {
  assert(name, "character")
  stopifnot(length(name) == 1)
  prop <- c("langlinks", "externallinks", "common_names", "classification")
  res <- wt_wiki_url_build(
    wiki = "species", type = "wikimedia", page = name,
    utf8 = utf8,
    prop = prop)
  pg <- wt_wiki_page(res, ...)
  wt_wikispecies_parse(pg, prop, tidy = TRUE)
}

#' @export
#' @rdname wt_wikispecies
wt_wikispecies_parse <- function(page, types = c("langlinks", "iwlinks",
                                              "externallinks", "common_names",
                                                 "classification"),
                                 tidy = FALSE) {

  result <- wt_wiki_page_parse(page, types = types, tidy = tidy)
  json <- jsonlite::fromJSON(rawToChar(page$content), simplifyVector = FALSE)
  if (is.null(json$parse)) {
    return(result)
  }
  ## Common names
  if ("common_names" %in% types) {
    xml <- xml2::read_html(json$parse$text[[1]])
    # XML formats:
    # <b>language:</b>&nbsp;[name|<a>name</a>]
    # Name formats:
    # name1, name2
    vernacular_html <- xml2::xml_find_all(
      xml,
      "(//h2[contains(@id, 'Vernacular')]/parent::*/following-sibling::div)[1]"
    )
    languages_html <- xml2::xml_find_all(vernacular_html, xpath = "b")
    languages <- gsub("\\s*:\\s*", "",
                      unlist(lapply(languages_html, xml2::xml_text)))
    names_html <-
      xml2::xml_find_all(
        vernacular_html,
    "b[not(following-sibling::*[1][self::a])]/following-sibling::text()[1] | b/following-sibling::*[1][self::a]/text()") #nolint
    common_names <- gsub("^\\s*", "",
                         unlist(lapply(names_html, xml2::xml_text)))
    cnms <-
      mapply(list, name = common_names,
             language = languages, SIMPLIFY = FALSE, USE.NAMES = FALSE)
    result$common_names <- if (tidy) atbl(dt_df(cnms)) else cnms
  }
  ## classification
  if ("classification" %in% types) {
    txt <- xml2::read_html(json$parse$text[[1]])
    html <- xml2::xml_text(
      xml2::xml_find_first(txt, "//table[contains(@class, \"wikitable\")]//p"))
    html <- strsplit(html, "\n")[[1]]
    labels <-
      vapply(html, function(z) strsplit(z, ":")[[1]][1], "", USE.NAMES = FALSE)
    values <-
      vapply(html, function(z) strsplit(z, ":")[[1]][2], "", USE.NAMES = FALSE)
    values <- gsub("^\\s+|\\s+$", "", values)
    clz <- mapply(list, rank = labels, name = values,
                  SIMPLIFY = FALSE, USE.NAMES = FALSE)
    result$classification <- if (tidy) atbl(dt_df(clz)) else clz
  }
  return(result)
}

#' @export
#' @rdname wt_wikispecies
wt_wikispecies_search <- function(query, limit = 10, offset = 0, utf8 = TRUE,
                                  ...) {
  tmp <- g_et(search_base("species"), sh(query, limit, offset, utf8), ...)
  tmp$query$search <- atbl(tmp$query$search)
  return(tmp)
}
