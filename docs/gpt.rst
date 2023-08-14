gpt
===

.. dfhack-tool::
    :summary: AI-generated written content!
    :tags: fort gameplay

Enables a UI for submitting knowledge item descriptions to OpenAI for generating
poetry, star charts, and excerpts from longer works such as biographies, dictionaries,
treatises on technological evolution, comparative biographies, cultural histories,
autobiographies, cultural comparisons, essays, guides, manuals, and more.

``enable gpt``
==============
Enables the plugin. The overlay will be shown when a knowledge item or unit view sheet is open.

``disable gpt``
===============
Disables the plugin.

Setup:

1. Register for an OpenAI API account. It must be a paid or active trial account.
2. Generate an API token for your account.
3. Save your OpenAI API token to a file at the root of your DF directory, `oaak.txt`.
4. Install python. We used version 3.11 installed from the Microsoft Store.
5. Install python dependencies Flask and OpenAI: `pip install Flask` and `pip install OpenAI`.
6. Start the local helper python app: cd into dfhack/scripts directory & run `python srv/gptserver.py`.

Once the python helper is running, you may now enable and use the gpt plugin.

The python script defaults to using the fast, cheap, legacy model `text-davinci-003`.
If you wish to use the slower, more expensive `gpt-3.5-turbo` or `gpt-4` models, you
can start the script with `python srv/gptserver.py -gpt3` or `python srv/gptserver.py -gpt4`.
Tweaking additional OpenAI API parameters will require modifying `gptserver.py` to suit
your particular needs.

Please refer to https://openai.com/pricing for current pricing information. As of Aug. 2023,
the price for a request/response using `-gpt3` mode would be expected to be two to three cents, &
OpenAI offers a free $5 trial API credit for 90 days when you first register.

Versions of python dependencies tested with:

Package            Version
------------------ ---------
aiohttp            3.8.5
aiosignal          1.3.1
async-timeout      4.0.2
attrs              23.1.0
blinker            1.6.2
certifi            2023.7.22
charset-normalizer 3.2.0
click              8.1.6
colorama           0.4.6
Flask              2.3.2
frozenlist         1.4.0
idna               3.4
itsdangerous       2.1.2
Jinja2             3.1.2
MarkupSafe         2.1.3
multidict          6.0.4
openai             0.27.8
requests           2.31.0
tqdm               4.65.0
urllib3            2.0.4
Werkzeug           2.3.6
yarl               1.9.2
