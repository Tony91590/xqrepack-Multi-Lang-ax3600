import threading
import os
from bs4 import BeautifulSoup
from lxml import etree
import requests
from google_trans_new import google_translator
import picklimport 

diccionario = {}
def traducir_texto(text):
    global diccionario
    text = text.strip()

    if text in diccionario:
        #print('[+] Ya en dict')
        return diccionario[text]
    else:     
        translator = google_translator()
        translated_text = (translator.translate(text, lang_tgt='fr'))

        if type(translated_text) == list:
           translated_text = translated_text[0] 
        diccionario[text] = translated_text
        return(translated_text)

counter = 1
def abrir_cambiar(archivo):
    global counter
    with open(archivo,'r') as f:
        content = f.read()

    soup = BeautifulSoup(content, "html.parser")
      
    dom = etree.HTML(str(soup))
    elementos = (dom.xpath('//*[text()]'))


    for elemento in elementos:
        try:
            if len(elemento.text.strip()) > 4:
                if "{" in elemento.text or "}" in elemento.text or ';' in elemento.text:
                    pass
                else:
                    texto_traducido = traducir_texto(elemento.text)
                    #REEMPLAZAR CON .STRIP
                    texto_a_trad = (elemento.text).strip()      
                    #print(texto_a_trad)
                    #print(texto_traducido)
                    content = content.replace(texto_a_trad,texto_traducido)
                    #print("success")
        except Exception as e:
            #print(e) 
            pass


    with open(archivo, 'w+') as f:
        f.write(content)

    counter += 1 



#counter = 1
for file in os.listdir():
    total = len([name for name in os.listdir('.') if os.path.isfile(name)])
    if not file.endswith(".py") and os.path.isfile(file):
        try:

            abrir_cambiar(file)            
            print('File succesfuly updated [{2}] ({0}/{1})'.format(counter, total, file))
        except Exception as e:
            print('[-] Perdido archivo: ', file)
            pass



