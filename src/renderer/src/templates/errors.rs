use askama::Template;
use color_eyre::Result;
use color_eyre::eyre::WrapErr;

pub(crate) struct ErrorEntry {
    pub(crate) page_name: String,
    pub(crate) detail: String,
}

#[derive(Template)]
#[template(path = "errors.html")]
struct ErrorPageTemplate<'a> {
    errors: &'a Vec<ErrorEntry>,
}

pub(crate) fn render(errors: &Vec<ErrorEntry>) -> Result<String> {
    ErrorPageTemplate { errors }
        .render()
        .wrap_err("Failed to render error list template")
}
