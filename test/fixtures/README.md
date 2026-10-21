fixtures
========

hand written json so the reader is tested on files the plugin did not write

file                              layout                          covers
types.json                        array of objects                text integers exact decimals exponents booleans null missing keys nested objects arrays empty object
envelope.json                     object with one records array   api envelope with meta and empty arrays around the records
two_arrays.json                   object with two records arrays  customers and orders in one document
offset.json                       array of arrays                 a title line and an empty line above the header
late_key.json                     array of objects                a key first seen in the last record
orders.jsonl                      a record per line               a blank line and a key first seen on the last line
cells.jsonl                       an array per line               a title line and an empty line above the header
orders_page.json                  object with one records array   an api page of orders with nested line arrays empty null and missing lines tags and a nested customer
golden/simple_joins/names.json    array of objects                refract core golden simple_joins names as json
golden/simple_joins/ages.jsonl    a record per line               refract core golden simple_joins ages as json lines
golden/simple_joins/expected.csv                                  copied from refract core golden simple_joins
