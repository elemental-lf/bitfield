#!/usr/bin/env python
import sys

version = '0.2.3'

try:
    from setuptools import setup, Extension
except ImportError:
    from distutils.core import setup, Extentsion

if '--use-cython' in sys.argv:
    USE_CYTHON = True
    sys.argv.remove('--use-cython')
else:
    USE_CYTHON = False

ext = '.pyx' if USE_CYTHON else '.c'
extentions = [Extension('sparsebitfield', ['cimpl/field' + ext], depends=['cimpl/field.h', 'cimpl/popcount.h'])]

if USE_CYTHON:
    from Cython.Build import cythonize
    extentions = cythonize(extentions, language_level=3)

with open("README.md", "r") as fh:
    long_description = fh.read()

setup(
    name='sparsebitfield',
    version=version,
    license='BSD',
    description='A Cython fast number set based on bitfields',
    long_description=long_description,
    long_description_content_type="text/markdown",
    author='Steve Stagg, Lars Fenneberg',
    author_email='stestagg@gmail.com, lf@elemental.net',
    url='http://github.com/elemental-lf/sparsebitfield',
    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'License :: OSI Approved :: BSD License',
        'Operating System :: OS Independent',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
    ],
    install_requires=[
        'sortedcontainers>=2.0.4',
    ],
    ext_modules=extentions,
)
