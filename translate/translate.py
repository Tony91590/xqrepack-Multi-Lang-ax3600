#!/usr/bin/env python

import sys, os, json, io, textwrap, fileinput
from google_trans_new import google_translator
from lxml import etree


class Translator:
	def __init__(self):
		self.unknownPhrases = set()
		self.LoadTranslateTable()
	def __del__(self):
		with io.open(os.path.join(self.scriptPath, 'unknownPhrases.txt'), 'w', encoding='utf-8') as file:
			for phrase in sorted(self.unknownPhrases):
				file.write(phrase + u"\n")
	
	def TranslateUnknownPhrases(self):
		jsonFilePath = os.path.join(self.scriptPath, "unknownPhrases.json")
		try:
			with io.open(jsonFilePath, 'r', encoding='utf-8') as file:
				data = json.load(file)
		except IOError as e:
			data = {}
		gt = google_translator()
		progress = .0
		for phrase in self.unknownPhrases:
			if phrase in data:
				continue
			trStr = gt.translate(phrase, lang_tgt='ru', lang_src='zh-tw')
			data[phrase] = trStr.strip()
			progress += 1
			print("Translating progress: %f"%(progress/len(self.unknownPhrases)*100), end = "\r")
		for phrase in list(data.keys()):
			if phrase not in self.unknownPhrases:
				del data[phrase]
		with io.open(jsonFilePath, 'w', encoding='utf-8') as file:
			json.dump(data, file, indent = 4, ensure_ascii=False)
		if progress > 0:
			print("Translating Done")
		
	@staticmethod
	def KeyComparatorLongAlpha(el):
		return (-len(el), el)
	
	def LoadTranslateTable(self):
		self.scriptPath = os.path.dirname(os.path.realpath(sys.argv[0]))
		with io.open(os.path.join(self.scriptPath, "zh_ru.json"), 'r', encoding='utf-8') as file:
			self.translateTable = json.load(file)
		self.keysToTranslate = sorted(self.translateTable.keys(), key=Translator.KeyComparatorLongAlpha);
	
	def TranslateFile(self, path):
		countPlaces = 0
		with io.open(path, 'r', encoding='utf-8') as file:
			filedata = file.read()
		for key in self.keysToTranslate:
			tmp = filedata.replace(key, self.translateTable[key])
			if not tmp is filedata:
				filedata = tmp
				countPlaces += 1
		if countPlaces > 0:
			with io.open(path, 'w', encoding='utf-8') as file:
				file.write(filedata)
			print("File: '{0}': {1}".format(path, countPlaces))
	
	@staticmethod
	def IsChinese(char):
		return True if ord(char) >= 0x4E00 else False
	
	@staticmethod
	def HasChinese(line):
		for s in line:
			if Translator.IsChinese(s):
				return True
		return False

	def CreateTableToTranslateBasedOnHtmlText(self, data):
		try:
			tree = etree.HTML(data)
			r = tree.xpath('//*[string-length(text()) > 0]')
		except:
			return []
		toReplace = []
		for v in r:
			if v.tag == 'script' or not v.text:
				continue
			text = v.text.strip()
			if not text:
				continue
			for line in text.split('\n'):
				self.CheckPhrase(line)
				toReplace.append(line)
		return sorted(toReplace, key=Translator.KeyComparatorLongAlpha)

	def CreateTableToTranslate(self, path):
		with io.open(path, 'r', encoding='utf-8') as file:
			data = file.read()
		
		keywords = [('<%:', '%>'),
						('<%', '%>'),
						('<!--', '-->'),
						('>', '<'),
						('\'', '\''),
						('"', '"'),
						('//', '\n')]
		for key1, key2 in keywords:
			if key1 == '>':
				toReplace = self.CreateTableToTranslateBasedOnHtmlText(data)
				for text in toReplace:
					data = data.replace(text, '')
				continue
			posS = -1
			posE = 0
			while True:
				posS = data.find(key1, posE)
				posSV = posS+len(key1)
				if posS == -1:
					break
				posE = data.find(key2, posSV)
				if posE != -1:
					phrase = data[posSV: posE]
					toRemove = key1 + phrase + key2
					data = data.replace(toRemove, '')
					posE = posS
				else:
					raise Exception("Unclosed {0} in {1}:{2}".format(key1, path, posS))
				if key1 in ['<%', '<!--', '//']:
					continue
				if phrase and phrase[0] == '<' and phrase[-1] == '>':
					toReplace = self.CreateTableToTranslateBasedOnHtmlText(phrase)
					if toReplace:
						for text in toReplace:
							data = data.replace(text, '')
						continue
				self.CheckPhrase(phrase)
		# raise Exception('FILE IS FOUND')
	
	def CheckPhrase(self, phrase):
		phrase = phrase.strip()
		if (phrase not in self.translateTable and
			phrase not in self.unknownPhrases and
			Translator.HasChinese(phrase)):
			tmp = phrase
			for key in self.keysToTranslate:
				tmp = tmp.replace(key, self.translateTable[key])
			if Translator.HasChinese(tmp):
				self.unknownPhrases.add(phrase)
			
			# print("=================================================================")
			# for line in textwrap.fill(phrase, 40).split('\n'):
				# marks = ""
				# for s in line:
					# marks += "^" if Translator.IsChinese(s) else '_'
				# print(u"{0}\n{1}".format(line, marks))
	
	def CheckFile(self, path, filedata):
		lineNum = 0;
		ret = True
		for line in filedata.split('\n'):
			lineNum += 1
			if Translator.HasChinese(line):
				# if ret:
					# print(path)
				# print(u"\t{0}: {1}".format(lineNum, line))
				ret = False
		if not ret:
			self.CreateTableToTranslate(path)
		return ret

def GetRootFolder():
	if len(sys.argv) == 2:
		return sys.argv[1]
	else:
		raise Exception("Root folder MUST be defined!")

def GetFilesToTranslate():
	path = GetRootFolder()
	filelist = []
	print("Path: {0}".format(path))
	for root, dirs, files in os.walk(path):
		for file in files:
			if file.endswith('.html') or file.endswith('.htm'):
				filelist.append(os.path.join(root,file))
	return filelist

def main():
	translator = Translator()
	
	for file in GetFilesToTranslate():
		translator.TranslateFile(file)
	translator.TranslateUnknownPhrases()
	print("\nDone\n")

main()